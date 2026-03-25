function main() {
    const grade = getGrade(85)
    println(`grade: ${grade}`)
}

function getGrade(score: int): string {
    if (score >= 90) {
        return "A"
    } else if (score >= 80) {
        return "B"
    } else {
        return "F"
    }
}
