import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public enum SSHClientError: Error {
    case notConnected
    case channelTypeRejected
    case authenticationUnavailable
    case hostKeyRejected
    case invalidChannelData
}

/// How the client authenticates. Secrets are supplied by the caller (the app
/// pulls them from the Keychain / Secure Enclave) and never persisted here.
public struct SSHCredentials {
    public enum Method {
        case password(String)
        /// A private key the caller already materialized. In Phase 3 this is
        /// produced by the Secure-Enclave-backed signer in the app layer.
        case privateKey(NIOSSHPrivateKey)
    }

    public var username: String
    public var method: Method

    public init(username: String, method: Method) {
        self.username = username
        self.method = method
    }
}

public struct HostKeyValidationContext: Sendable {
    public let host: String
    public let port: Int
}

public enum HostKeyValidationResult: Sendable {
    case accept
    case reject
}

/// Thin async wrapper around SwiftNIO SSH: connect + authenticate, then open an
/// interactive shell channel with a PTY. Output is delivered as an async stream;
/// keystrokes and window-resize events are sent back through the `ShellSession`.
public final class SSHClient {
    private let group: EventLoopGroup
    private let ownsGroup: Bool
    private var channel: Channel?
    private var sshHandler: NIOSSHHandler?

    public init(group: EventLoopGroup? = nil) {
        if let group {
            self.group = group
            self.ownsGroup = false
        } else {
            self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            self.ownsGroup = true
        }
    }

    public func connect(
        host: String,
        port: Int,
        credentials: SSHCredentials,
        hostKeyValidator: @escaping (NIOSSHPublicKey, HostKeyValidationContext) -> HostKeyValidationResult
    ) async throws {
        let authDelegate = CredentialAuthDelegate(username: credentials.username, method: credentials.method)
        let hostKeyDelegate = ValidatingHostKeyDelegate(host: host, port: port, validator: hostKeyValidator)

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let handler = NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: authDelegate,
                            serverAuthDelegate: hostKeyDelegate
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    try channel.pipeline.syncOperations.addHandler(handler)
                }
            }

        let channel = try await bootstrap.connect(host: host, port: port).get()
        self.channel = channel
        self.sshHandler = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()
    }

    public func startShell(
        term: String = "xterm-256color",
        cols: Int = 80,
        rows: Int = 24
    ) async throws -> ShellSession {
        guard let sshHandler, let channel else { throw SSHClientError.notConnected }

        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let handler = ShellChannelHandler(
            term: term,
            cols: cols,
            rows: rows,
            onData: { continuation.yield($0) },
            onClose: { continuation.finish() }
        )

        let promise = channel.eventLoop.makePromise(of: Channel.self)
        sshHandler.createChannel(promise) { childChannel, channelType in
            guard channelType == .session else {
                return childChannel.eventLoop.makeFailedFuture(SSHClientError.channelTypeRejected)
            }
            return childChannel.pipeline.addHandler(handler)
        }

        let childChannel = try await promise.futureResult.get()
        return ShellSession(channel: childChannel, output: stream, continuation: continuation)
    }

    public func disconnect() async {
        if let channel {
            try? await channel.close().get()
        }
        channel = nil
        sshHandler = nil
        if ownsGroup {
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                group.shutdownGracefully { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}

/// A live interactive shell. Output arrives via `output`; input and resize events
/// are pushed back through `send`/`resize`.
public struct ShellSession {
    private let channel: Channel
    public let output: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init(
        channel: Channel,
        output: AsyncThrowingStream<Data, Error>,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        self.channel = channel
        self.output = output
        self.continuation = continuation
    }

    public func send(_ data: Data) async throws {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await channel.writeAndFlush(buffer).get()
    }

    public func sendText(_ text: String) async throws {
        try await send(Data(text.utf8))
    }

    public func resize(cols: Int, rows: Int) async throws {
        let event = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        try await channel.triggerUserOutboundEvent(event).get()
    }

    public func close() async {
        continuation.finish()
        try? await channel.close().get()
    }
}

// MARK: - NIOSSH delegates & handlers

final class CredentialAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let method: SSHCredentials.Method
    private var attempted = false

    init(username: String, method: SSHCredentials.Method) {
        self.username = username
        self.method = method
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        // We only offer a single credential; if it isn't accepted, give up rather
        // than loop forever.
        guard !attempted else {
            nextChallengePromise.succeed(nil)
            return
        }
        attempted = true

        let offer: NIOSSHUserAuthenticationOffer.Offer
        switch method {
        case .password(let password):
            guard availableMethods.contains(.password) else {
                nextChallengePromise.succeed(nil)
                return
            }
            offer = .password(.init(password: password))
        case .privateKey(let key):
            guard availableMethods.contains(.publicKey) else {
                nextChallengePromise.succeed(nil)
                return
            }
            offer = .privateKey(.init(privateKey: key))
        }

        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: offer)
        )
    }
}

final class ValidatingHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int
    private let validator: (NIOSSHPublicKey, HostKeyValidationContext) -> HostKeyValidationResult

    init(
        host: String,
        port: Int,
        validator: @escaping (NIOSSHPublicKey, HostKeyValidationContext) -> HostKeyValidationResult
    ) {
        self.host = host
        self.port = port
        self.validator = validator
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let context = HostKeyValidationContext(host: host, port: port)
        switch validator(hostKey, context) {
        case .accept:
            validationCompletePromise.succeed(())
        case .reject:
            validationCompletePromise.fail(SSHClientError.hostKeyRejected)
        }
    }
}

/// Bridges an SSH session child channel to byte streams: requests a PTY + shell on
/// add, forwards inbound channel data out as `Data`, and wraps outbound bytes back
/// into `SSHChannelData`.
final class ShellChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let term: String
    private let cols: Int
    private let rows: Int
    private let onData: (Data) -> Void
    private let onClose: () -> Void

    init(
        term: String,
        cols: Int,
        rows: Int,
        onData: @escaping (Data) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.term = term
        self.cols = cols
        self.rows = rows
        self.onData = onData
        self.onClose = onClose
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: term,
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        context.triggerUserOutboundEvent(ptyRequest, promise: nil)

        let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: true)
        context.triggerUserOutboundEvent(shellRequest, promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = channelData.data else {
            context.fireErrorCaught(SSHClientError.invalidChannelData)
            return
        }
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
            onData(Data(bytes))
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)
        let wrapped = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        context.write(self.wrapOutboundOut(wrapped), promise: promise)
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose()
        context.fireChannelInactive()
    }
}
