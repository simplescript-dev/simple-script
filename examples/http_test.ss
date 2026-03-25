function main() {
    const server = tcpListen(8081)
    println("listening on 8081, fd=" + server)
    const client = tcpAccept(server)
    println("accepted, fd=" + client)
    const data = tcpRead(client, 1024)
    println("read: " + data.length() + " bytes")
    println("first line: " + data.substring(0, 40))
    const resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
    println("writing " + resp.length() + " bytes")
    const written = tcpWrite(client, resp)
    println("written: " + written)
    tcpClose(client)
    tcpClose(server)
    println("done")
}
