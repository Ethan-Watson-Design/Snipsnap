//
//  AnnotatedVideoExporter.swift
//  Grabbit
//

import AppKit
@preconcurrency import AVFoundation
import CoreImage

enum AnnotatedVideoExporter {

    enum ExportError: LocalizedError {
        case noVideoTrack
        case readerSetupFailed
        case writerSetupFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "The recording has no video track."
            case .readerSetupFailed: return "Could not read the recording."
            case .writerSetupFailed: return "Could not create the annotated video."
            case .exportFailed(let detail): return detail
            }
        }
    }

    private static func runAsync<T>(_ work: @escaping () async throws -> T) throws -> T {
        var outcome: Result<T, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                outcome = .success(try await work())
            } catch {
                outcome = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let outcome else {
            throw ExportError.exportFailed("Export was interrupted.")
        }
        return try outcome.get()
    }

    static func export(
        sourceURL: URL,
        snapshot: AnnotationExportSnapshot,
        renderer: AnnotationCanvasView,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outputURL = try exportSynchronously(
                    sourceURL: sourceURL,
                    snapshot: snapshot,
                    renderer: renderer
                )
                DispatchQueue.main.async { completion(.success(outputURL)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func needsCompositedExport(snapshot: AnnotationExportSnapshot) -> Bool {
        for placed in snapshot.annotations {
            if case .zoom = placed.content { continue }
            return true
        }
        return snapshot.annotations.contains { if case .zoom = $0.content { return true }; return false }
    }

    private static func hasDrawnAnnotations(_ annotations: [PlacedAnnotation]) -> Bool {
        annotations.contains { placed in
            if case .zoom = placed.content { return false }
            return true
        }
    }

    private static func exportSynchronously(
        sourceURL: URL,
        snapshot: AnnotationExportSnapshot,
        renderer: AnnotationCanvasView
    ) throws -> URL {
        if !needsCompositedExport(snapshot: snapshot) {
            return sourceURL
        }

        let outputDirectory = sourceURL.deletingLastPathComponent()
        let annotatedStem = "\(sourceURL.deletingPathExtension().lastPathComponent) (annotated)"
        let preferredFilename = "\(annotatedStem).mp4"
        let finalURL = CaptureNaming.uniqueURL(in: outputDirectory, preferredFilename: preferredFilename)

        try renderCompositedVideo(
            sourceURL: sourceURL,
            snapshot: snapshot,
            renderer: renderer,
            to: finalURL
        )
        return finalURL
    }

    private static func renderCompositedVideo(
        sourceURL: URL,
        snapshot: AnnotationExportSnapshot,
        renderer: AnnotationCanvasView,
        to finalURL: URL
    ) throws {
        let zoomAnnotations = snapshot.annotations.filter {
            if case .zoom = $0.content { return true }
            return false
        }

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try runAsync { try await asset.loadTracks(withMediaType: .video) }
        guard let videoTrack = videoTracks.first else {
            throw ExportError.noVideoTrack
        }

        let naturalSize = try runAsync { try await videoTrack.load(.naturalSize) }
        let transform = try runAsync { try await videoTrack.load(.preferredTransform) }
        let transformed = naturalSize.applying(transform)
        let pixelWidth = Int(abs(transformed.width).rounded())
        let pixelHeight = Int(abs(transformed.height).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw ExportError.readerSetupFailed
        }

        let outputSize = CGSize(width: pixelWidth, height: pixelHeight)
        let duration = try runAsync { try await asset.load(.duration) }
        let audioTracks = try runAsync { try await asset.loadTracks(withMediaType: .audio) }
        let hasAudio = !audioTracks.isEmpty

        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        defer {
            try? FileManager.default.removeItem(at: tempVideoURL)
        }

        try renderAnnotatedVideo(
            asset: asset,
            videoTrack: videoTrack,
            transform: transform,
            outputSize: outputSize,
            snapshot: snapshot,
            renderer: renderer,
            zoomAnnotations: zoomAnnotations,
            to: tempVideoURL
        )

        if hasAudio {
            try muxAudio(from: sourceURL, videoURL: tempVideoURL, outputURL: finalURL, duration: duration)
        } else {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.copyItem(at: tempVideoURL, to: finalURL)
        }
    }

    private static func renderAnnotatedVideo(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        transform: CGAffineTransform,
        outputSize: CGSize,
        snapshot: AnnotationExportSnapshot,
        renderer: AnnotationCanvasView,
        zoomAnnotations: [PlacedAnnotation],
        to outputURL: URL
    ) throws {
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ExportError.readerSetupFailed }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height)
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(writerInput) else { throw ExportError.writerSetupFailed }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw ExportError.readerSetupFailed
        }
        guard writer.startWriting() else {
            throw ExportError.writerSetupFailed
        }

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var sessionStarted = false
        let canvasSize = snapshot.canvasSize
        let annotations = snapshot.annotations
        let hasDrawn = hasDrawnAnnotations(annotations)
        let outputRect = CGRect(origin: .zero, size: outputSize)

        while reader.status == .reading {
            let processedFrame = autoreleasepool { () -> Bool in
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                      let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return false
                }

                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if !sessionStarted {
                    writer.startSession(atSourceTime: presentationTime)
                    sessionStarted = true
                }

                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.005)
                }

                var ciImage = CIImage(cvPixelBuffer: sourceBuffer)
                if transform != .identity {
                    ciImage = ciImage.transformed(by: transform)
                    let extent = ciImage.extent
                    if extent.origin.x != 0 || extent.origin.y != 0 {
                        ciImage = ciImage.transformed(
                            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
                        )
                    }
                }
                ciImage = ciImage.cropped(to: outputRect)

                let time = CMTimeGetSeconds(presentationTime)
                let zoom = ZoomEffect.transform(
                    at: time,
                    from: zoomAnnotations,
                    outputSize: outputSize,
                    canvasSize: canvasSize,
                    mediaSize: outputSize
                )
                if abs(zoom.scale - 1) > 0.001 || zoom.panProgress > 0.001 {
                    ciImage = ZoomEffect.applyZoom(to: ciImage, zoom: zoom, outputSize: outputSize)
                }

                guard let pool = adaptor.pixelBufferPool else { return true }

                if hasDrawn {
                    guard let cgImage = ciContext.createCGImage(ciImage, from: outputRect) else { return true }

                    let frame = NSImage(cgImage: cgImage, size: outputSize)
                    let composited: NSImage
                    if Thread.isMainThread {
                        composited = renderer.flattenedImageForExport(
                            background: frame,
                            at: time,
                            outputSize: outputSize,
                            mapFromCanvasSize: canvasSize,
                            annotations: annotations
                        )
                    } else {
                        composited = DispatchQueue.main.sync {
                            renderer.flattenedImageForExport(
                                background: frame,
                                at: time,
                                outputSize: outputSize,
                                mapFromCanvasSize: canvasSize,
                                annotations: annotations
                            )
                        }
                    }

                    guard let pixelBuffer = makePixelBuffer(from: composited, size: outputSize, pool: pool) else {
                        return true
                    }
                    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                } else {
                    guard let pixelBuffer = makePixelBuffer(from: ciImage, size: outputSize, pool: pool, context: ciContext, colorSpace: colorSpace) else {
                        return true
                    }
                    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                }

                return true
            }

            if !processedFrame { break }
        }

        writerInput.markAsFinished()
        let group = DispatchGroup()
        group.enter()
        writer.finishWriting {
            group.leave()
        }
        group.wait()

        guard writer.status == .completed else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Video export failed.")
        }
    }

    private static func muxAudio(
        from sourceURL: URL,
        videoURL: URL,
        outputURL: URL,
        duration: CMTime
    ) throws {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let videoAsset = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()

        let sourceVideoTracks = try runAsync { try await videoAsset.loadTracks(withMediaType: .video) }
        guard let sourceVideoTrack = sourceVideoTracks.first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw ExportError.exportFailed("Could not combine audio and video.")
        }

        let videoDuration = try runAsync { try await videoAsset.load(.duration) }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )

        let sourceAudioTracks = try runAsync { try await sourceAsset.loadTracks(withMediaType: .audio) }
        if let sourceAudioTrack = sourceAudioTracks.first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let sourceDuration = try runAsync { try await sourceAsset.load(.duration) }
            let audioDuration = min(sourceDuration, duration)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioDuration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not finalize the annotated video.")
        }

        try runAsync {
            try await exportSession.export(to: outputURL, as: .mp4)
        }
    }

    private static func makePixelBuffer(
        from image: CIImage,
        size: CGSize,
        pool: CVPixelBufferPool,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        context.render(
            image,
            to: buffer,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: colorSpace
        )
        return buffer
    }

    private static func makePixelBuffer(
        from image: NSImage,
        size: CGSize,
        pool: CVPixelBufferPool
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.clear(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else { return nil }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }

}
