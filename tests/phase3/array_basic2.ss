function main() {
    const nums = [10, 20, 30, 40, 50]
    println(`nums[0] = ${nums[0]}`)
    println(`nums[2] = ${nums[2]}`)
    nums[2] = 99
    println(`nums[2] = ${nums[2]}`)

    let sum = 0
    for (let i = 0; i < 5; i++) {
        sum = sum + nums[i]
    }
    println(`sum = ${sum}`)
}
