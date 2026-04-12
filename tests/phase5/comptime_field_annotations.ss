// Test: field-level annotations accessible via getTypeInfo() reflection

import { assertEqual } from "@/lib/test"

class User {
    @Id
    id: int

    @Column("user_name")
    name: string

    @Column("user_email")
    @NotNull
    email: string

    score: int
}

comptime {
    const info = getTypeInfo("User")

    let fieldCount = info.fields.length()
    let idAnnCount = 0
    let idAnnName = ""
    let nameAnnCount = 0
    let nameAnnName = ""
    let nameAnnArg = ""
    let emailAnnCount = 0
    let emailAnn0Name = ""
    let emailAnn0Arg = ""
    let emailAnn1Name = ""
    let scoreAnnCount = 0

    for (f in info.fields) {
        if (f.name == "id") {
            idAnnCount = f.annotations.length()
            if (idAnnCount > 0) { idAnnName = f.annotations[0].name }
        }
        if (f.name == "name") {
            nameAnnCount = f.annotations.length()
            if (nameAnnCount > 0) {
                nameAnnName = f.annotations[0].name
                nameAnnArg = f.annotations[0].args
            }
        }
        if (f.name == "email") {
            emailAnnCount = f.annotations.length()
            if (emailAnnCount > 0) {
                emailAnn0Name = f.annotations[0].name
                emailAnn0Arg = f.annotations[0].args
            }
            if (emailAnnCount > 1) {
                emailAnn1Name = f.annotations[1].name
            }
        }
        if (f.name == "score") {
            scoreAnnCount = f.annotations.length()
        }
    }

    @comptimeEmit(`
function testFieldCount(): int { return ${fieldCount} }
function testIdAnnCount(): int { return ${idAnnCount} }
function testIdAnnName(): string { return "${idAnnName}" }
function testNameAnnCount(): int { return ${nameAnnCount} }
function testNameAnnName(): string { return "${nameAnnName}" }
function testNameAnnArg(): string { return "${nameAnnArg}" }
function testEmailAnnCount(): int { return ${emailAnnCount} }
function testEmailAnn0Name(): string { return "${emailAnn0Name}" }
function testEmailAnn0Arg(): string { return "${emailAnn0Arg}" }
function testEmailAnn1Name(): string { return "${emailAnn1Name}" }
function testScoreAnnCount(): int { return ${scoreAnnCount} }
`)
}

function main() {
    test("field count", () => {
        assertEqual(testFieldCount(), 4)
    })
    test("@Id on id field", () => {
        assertEqual(testIdAnnCount(), 1)
        assertEqual(testIdAnnName(), "Id")
    })
    test("@Column with arg on name field", () => {
        assertEqual(testNameAnnCount(), 1)
        assertEqual(testNameAnnName(), "Column")
        assertEqual(testNameAnnArg(), "user_name")
    })
    test("multiple annotations on email field", () => {
        assertEqual(testEmailAnnCount(), 2)
        assertEqual(testEmailAnn0Name(), "Column")
        assertEqual(testEmailAnn0Arg(), "user_email")
        assertEqual(testEmailAnn1Name(), "NotNull")
    })
    test("no annotations on score field", () => {
        assertEqual(testScoreAnnCount(), 0)
    })
}
