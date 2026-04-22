// shell builtin: 捕获命令 stdout 作 RC string

function main() {
    const out = shell("echo hello_shell")
    if (out != "hello_shell\n") { exit(1) }

    const lsOut = shell("ls bootstrap/gen/rt/ | grep gen_rt_shell")
    if (lsOut != "gen_rt_shell.ss\n") { exit(2) }
}
