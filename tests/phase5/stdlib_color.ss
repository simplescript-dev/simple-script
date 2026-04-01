// Test: Color standard library module (D045)

import { Color } from "@/lib/color"
import { Assert } from "@/lib/assert"

function main() {
    const esc = fromCharCode(27)

    // ── Modifiers ────────────────────────────────────────────
    Assert.equal(Color.bold("hi"), `${esc}[1mhi${esc}[22m`, "bold")
    Assert.equal(Color.dim("hi"), `${esc}[2mhi${esc}[22m`, "dim")
    Assert.equal(Color.italic("hi"), `${esc}[3mhi${esc}[23m`, "italic")
    Assert.equal(Color.underline("hi"), `${esc}[4mhi${esc}[24m`, "underline")
    Assert.equal(Color.inverse("hi"), `${esc}[7mhi${esc}[27m`, "inverse")
    Assert.equal(Color.strikethrough("hi"), `${esc}[9mhi${esc}[29m`, "strikethrough")

    // ── Foreground colors ────────────────────────────────────
    Assert.equal(Color.black("x"), `${esc}[30mx${esc}[39m`, "black")
    Assert.equal(Color.red("x"), `${esc}[31mx${esc}[39m`, "red")
    Assert.equal(Color.green("x"), `${esc}[32mx${esc}[39m`, "green")
    Assert.equal(Color.yellow("x"), `${esc}[33mx${esc}[39m`, "yellow")
    Assert.equal(Color.blue("x"), `${esc}[34mx${esc}[39m`, "blue")
    Assert.equal(Color.magenta("x"), `${esc}[35mx${esc}[39m`, "magenta")
    Assert.equal(Color.cyan("x"), `${esc}[36mx${esc}[39m`, "cyan")
    Assert.equal(Color.white("x"), `${esc}[37mx${esc}[39m`, "white")

    // ── Bright foreground colors ─────────────────────────────
    Assert.equal(Color.gray("x"), `${esc}[90mx${esc}[39m`, "gray")
    Assert.equal(Color.brightRed("x"), `${esc}[91mx${esc}[39m`, "brightRed")
    Assert.equal(Color.brightGreen("x"), `${esc}[92mx${esc}[39m`, "brightGreen")
    Assert.equal(Color.brightYellow("x"), `${esc}[93mx${esc}[39m`, "brightYellow")
    Assert.equal(Color.brightBlue("x"), `${esc}[94mx${esc}[39m`, "brightBlue")
    Assert.equal(Color.brightMagenta("x"), `${esc}[95mx${esc}[39m`, "brightMagenta")
    Assert.equal(Color.brightCyan("x"), `${esc}[96mx${esc}[39m`, "brightCyan")
    Assert.equal(Color.brightWhite("x"), `${esc}[97mx${esc}[39m`, "brightWhite")

    // ── Background colors ────────────────────────────────────
    Assert.equal(Color.bgBlack("x"), `${esc}[40mx${esc}[49m`, "bgBlack")
    Assert.equal(Color.bgRed("x"), `${esc}[41mx${esc}[49m`, "bgRed")
    Assert.equal(Color.bgGreen("x"), `${esc}[42mx${esc}[49m`, "bgGreen")
    Assert.equal(Color.bgYellow("x"), `${esc}[43mx${esc}[49m`, "bgYellow")
    Assert.equal(Color.bgBlue("x"), `${esc}[44mx${esc}[49m`, "bgBlue")
    Assert.equal(Color.bgMagenta("x"), `${esc}[45mx${esc}[49m`, "bgMagenta")
    Assert.equal(Color.bgCyan("x"), `${esc}[46mx${esc}[49m`, "bgCyan")
    Assert.equal(Color.bgWhite("x"), `${esc}[47mx${esc}[49m`, "bgWhite")

    // ── Composition (nesting) ────────────────────────────────
    const boldRed = Color.bold(Color.red("error"))
    Assert.equal(boldRed, `${esc}[1m${esc}[31merror${esc}[39m${esc}[22m`, "bold+red")

    const bgWarn = Color.bgYellow(Color.black("warn"))
    Assert.equal(bgWarn, `${esc}[43m${esc}[30mwarn${esc}[39m${esc}[49m`, "bg+fg combo")

    // ── strip ────────────────────────────────────────────────
    Assert.equal(Color.strip(Color.red("hello")), "hello", "strip red")
    Assert.equal(Color.strip(Color.bold(Color.green("ok"))), "ok", "strip bold+green")
    Assert.equal(Color.strip("no colors"), "no colors", "strip plain text")
    Assert.equal(Color.strip(""), "", "strip empty")

    // ── reset ────────────────────────────────────────────────
    Assert.equal(Color.reset(), `${esc}[0m`, "reset sequence")

    // ── Empty string ─────────────────────────────────────────
    Assert.equal(Color.red(""), `${esc}[31m${esc}[39m`, "color empty string")
    Assert.equal(Color.strip(Color.red("")), "", "strip colored empty")

    println("All color tests passed!")
}
