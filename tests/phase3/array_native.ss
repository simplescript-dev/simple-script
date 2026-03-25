function main() {
    // Array literal
    const nums = [10, 20, 30, 40, 50]

    // Index access
    println(`nums[0] = ${nums[0]}`)
    println(`nums[2] = ${nums[2]}`)
    println(`nums[4] = ${nums[4]}`)

    // Index assignment
    nums[2] = 99
    println(`nums[2] after set = ${nums[2]}`)

    // Loop over array
    let sum = 0
    for (let i = 0; i < 5; i++) {
        sum = sum + nums[i]
    }
    println(`sum = ${sum}`)

    // Sort
    const data = [5, 3, 8, 1, 9, 2, 7, 4, 6]
    sort(data, 9)
    print("sorted: ")
    for (let i = 0; i < 9; i++) {
        print(`${data[i]} `)
    }
    println("")
}

function sort(arr: string, n: int) {
    for (let i = 0; i < n - 1; i++) {
        for (let j = 0; j < n - 1 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                const tmp = arr[j]
                arr[j] = arr[j + 1]
                arr[j + 1] = tmp
            }
        }
    }
}
