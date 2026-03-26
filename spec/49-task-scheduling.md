# 49 - Task Scheduling (定时任务)

## 设计理念

> 注解声明定时任务，编译器生成调度代码。不需要外部 cron 或定时器框架。

## 基本用法

```simplescript
import { Scheduled, FixedRate, Cron } from "ss/schedule"
import { Service } from "ss/di"

@Service
class ScheduledTasks {

    // 每 60 秒执行一次
    @Scheduled(fixedRate: 60000)
    function healthCheck() {
        const status = checkAllServices()
        if (!status.isHealthy()) {
            alertOps(status)
        }
    }

    // 每 5 分钟，上一次执行完后开始计时
    @Scheduled(fixedDelay: 300000)
    function syncData() {
        fetchAndSync()
    }

    // cron 表达式
    @Scheduled(cron: "0 0 * * *")       // 每天零点
    function dailyReport() {
        const report = generateReport()
        sendToSlack(report)
    }

    @Scheduled(cron: "0 0 * * 1")       // 每周一零点
    function weeklyCleanup() {
        db.execute("DELETE FROM logs WHERE created_at < NOW() - INTERVAL 30 DAY")
    }

    // 启动后延迟 10 秒执行一次
    @Scheduled(initialDelay: 10000)
    function warmUpCache() {
        cacheService.warmUp()
    }
}
```

## 动态调度

```simplescript
import { TaskScheduler, Task } from "ss/schedule"

@Service
class DynamicScheduler(scheduler: TaskScheduler) {

    function scheduleReminder(userId: long, message: string, delayMs: long) {
        scheduler.schedule(delayMs, () => {
            notifyUser(userId, message)
        })
    }

    function scheduleRecurring(name: string, intervalMs: long, action: () => void): Task {
        return scheduler.scheduleAtFixedRate(intervalMs, action)
    }

    function cancelTask(task: Task) {
        task.cancel()
    }
}
```
