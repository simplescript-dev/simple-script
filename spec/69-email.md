# 69 - Email (邮件发送)

## 设计理念

> 邮件发送是常见需求。官方包封装 SMTP，支持模板邮件。

## 基本发送

```simplescript
import { EmailSender, Email } from "ss/email"
import { Service } from "ss/di"

@Service
class NotificationService(email: EmailSender) {

    function sendWelcome(to: string, name: string) {
        email.send(new Email(
            to: to,
            subject: "Welcome!",
            body: `Hello ${name}, welcome to our platform!`
        ))
    }

    function sendWithAttachment(to: string) {
        email.send(new Email(
            to: to,
            subject: "Monthly Report",
            body: "Please find the report attached.",
            attachments: List.of(
                Email.attachment("report.pdf", readFile("reports/march.pdf")?)
            )
        ))
    }
}
```

## HTML 模板邮件

```simplescript
import { EmailSender, TemplateEmail } from "ss/email"
import { Template } from "ss/template"

@Service
class NotificationService(email: EmailSender) {

    function sendWelcome(to: string, name: string) {
        email.sendTemplate(new TemplateEmail(
            to: to,
            subject: "Welcome!",
            template: "emails/welcome.html",
            data: Map.of(
                ["name", name],
                ["loginUrl", "https://example.com/login"]
            )
        ))
    }
}
```

```html
<!-- resources/emails/welcome.html -->
<!DOCTYPE html>
<html>
<body>
    <h1>Welcome, ${name}!</h1>
    <p>Your account has been created.</p>
    <a href="${loginUrl}">Login Now</a>
</body>
</html>
```

## 多收件人

```simplescript
email.send(new Email(
    to: "alice@example.com",
    cc: List.of("bob@example.com"),
    bcc: List.of("admin@example.com"),
    subject: "Team Update",
    body: "..."
))
```

## 配置

```yaml
# application.yml
email:
  host: smtp.example.com
  port: 587
  username: noreply@example.com
  password: ${SMTP_PASSWORD}
  from: "MyApp <noreply@example.com>"
  tls: true
```
