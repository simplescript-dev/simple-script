# 52 - File Upload & Multipart (文件上传)

## 设计理念

> HTTP 文件上传是 Web 开发基本需求。标准注解处理，不需要手动解析 multipart。

## 基本上传

```simplescript
import { RestController, PostMapping, MultipartFile } from "yummy/web"
import { Response } from "net/http"
import { writeFile } from "io/fs"

@RestController
class UploadController {

    @PostMapping("/upload")
    function upload(@MultipartFile file: UploadedFile): Response {
        // 文件信息
        println(`name: ${file.name}`)
        println(`size: ${file.size}`)
        println(`type: ${file.contentType}`)

        // 保存到磁盘
        writeFile(`uploads/${file.name}`, file.bytes)?

        return Response.ok(Map.of(
            ["filename", file.name],
            ["size", file.size]
        ))
    }
}
```

## 多文件上传

```simplescript
@RestController
class UploadController {

    @PostMapping("/upload/batch")
    function uploadBatch(@MultipartFile files: List<UploadedFile>): Response {
        let savedCount = 0
        for (file in files) {
            writeFile(`uploads/${file.name}`, file.bytes)?
            savedCount++
        }
        return Response.ok(Map.of(["saved", savedCount]))
    }
}
```

## 文件校验

```simplescript
import { MaxFileSize, AllowedTypes } from "yummy/web"

@RestController
class UploadController {

    @PostMapping("/upload/avatar")
    function uploadAvatar(
        @MultipartFile
        @MaxFileSize(5 * 1024 * 1024)              // 最大 5MB
        @AllowedTypes(["image/jpeg", "image/png"])   // 只允许图片
        file: UploadedFile
    ): Response {
        // 校验不通过自动返回 400
        const path = `avatars/${generateId()}.${file.extension}`
        writeFile(path, file.bytes)?
        return Response.ok(Map.of(["path", path]))
    }
}
```

## 流式上传 (大文件)

```simplescript
@RestController
class UploadController {

    @PostMapping("/upload/large")
    function uploadLarge(@MultipartFile stream: FileStream): Response {
        // 不把整个文件加载到内存，流式写入
        try (const writer = File.writer("uploads/large_file.dat")?) {
            let totalBytes: long = 0
            const buffer = new Array<ubyte>(8192)

            while (true) {
                const bytesRead = stream.read(buffer)
                if (bytesRead <= 0) break
                writer.write(buffer, 0, bytesRead)
                totalBytes += bytesRead
            }

            return Response.ok(Map.of(["size", totalBytes]))
        }
    }
}
```

## 文件下载

```simplescript
@RestController
class DownloadController {

    @GetMapping("/download/:filename")
    function download(@PathVariable filename: string): Response {
        const path = `uploads/${filename}`
        if (!File.exists(path)) return Response.notFound("file not found")

        return Response.file(path)     // 自动设置 Content-Type 和 Content-Disposition
    }

    @GetMapping("/export/report")
    function exportReport(): Response {
        const csv = generateCsvReport()
        return Response.download(csv.toBytes(), "report.csv", "text/csv")
    }
}
```
