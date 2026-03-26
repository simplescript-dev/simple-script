# 68 - Async Task & Background Jobs (异步任务与后台作业)

## 设计理念

> 耗时操作放到后台虚拟线程执行，立即返回结果。
> 任务持久化，崩溃后可恢复。

## 简单后台任务

```simplescript
import { Service } from "ss/di"

@Service
class ReportService {

    function generateReport(userId: long): string {
        // spawn 启动虚拟线程，立即返回任务 ID
        const taskId = generateId()

        spawn {
            const data = fetchAllData(userId)        // 耗时
            const report = buildReport(data)          // 耗时
            saveReport(taskId, report)
        }

        return taskId    // 立即返回
    }

    function getReportStatus(taskId: string): ReportStatus {
        return reportStore.getStatus(taskId)
    }
}
```

## API 模式: 异步请求 + 轮询

```simplescript
@RestController
@RequestMapping("/api/reports")
class ReportController(reportService: ReportService) {

    // 提交任务
    @PostMapping
    function create(@RequestBody req: ReportRequest): Response {
        const taskId = reportService.generateReport(req.userId)
        return Response.accepted(Map.of(
            ["taskId", taskId],
            ["statusUrl", `/api/reports/${taskId}/status`]
        ))
    }

    // 查询状态
    @GetMapping("/:taskId/status")
    function status(@PathVariable taskId: string): Response {
        const status = reportService.getReportStatus(taskId)
        return switch (status) {
            case ReportStatus.Pending -> Response.ok(Map.of(["status", "pending"]))
            case ReportStatus.Processing -> Response.ok(Map.of(["status", "processing"]))
            case ReportStatus.Done d -> Response.ok(Map.of(
                ["status", "done"],
                ["downloadUrl", `/api/reports/${taskId}/download`]
            ))
            case ReportStatus.Failed f -> Response.ok(Map.of(
                ["status", "failed"],
                ["error", f.message]
            ))
        }
    }

    // 下载结果
    @GetMapping("/:taskId/download")
    function download(@PathVariable taskId: string): Response {
        const report = reportService.getReport(taskId)?
        return Response.download(report.toBytes(), "report.csv", "text/csv")
    }
}
```

## 持久化任务队列

```simplescript
import { Job, JobQueue, JobHandler } from "ss/jobs"
import { Service } from "ss/di"

// 定义 Job
class SendEmailJob(to: string, subject: string, body: string) : Job

class ResizeImageJob(imagePath: string, width: int, height: int) : Job

// 注册 Handler
@Service
class EmailJobHandler : JobHandler<SendEmailJob> {
    override function handle(job: SendEmailJob) {
        smtpClient.send(job.to, job.subject, job.body)
    }
}

@Service
class ImageJobHandler : JobHandler<ResizeImageJob> {
    override function handle(job: ResizeImageJob) {
        const image = loadImage(job.imagePath)
        const resized = image.resize(job.width, job.height)
        saveImage(resized, job.imagePath)
    }
}

// 提交任务
@Service
class UserService(jobQueue: JobQueue) {
    function register(user: User) {
        db.insert(user)
        // 投入队列，异步处理
        jobQueue.enqueue(new SendEmailJob(user.email, "Welcome", `Hi ${user.name}!`))
    }
}
```

## 配置

```yaml
# application.yml
jobs:
  store: database          # memory | database | redis
  workers: 4               # 并行 worker 数
  retries: 3               # 失败最大重试
  retryDelay: 5000         # 重试间隔 ms
  timeout: 300000          # 任务超时 5 分钟
```
