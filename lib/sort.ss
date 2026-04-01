// SimpleScript Sort Library — sorting algorithms and utilities for Array<int>
//
// Usage:
//   import { Sort } from "@/lib/sort"
//
//   let sorted = Sort.quickSort([5, 3, 8, 1])   // [1, 3, 5, 8]
//   Sort.isSorted(sorted)                         // 1
//   Sort.binarySearch(sorted, 3)                  // 1
//   Sort.min([4, 2, 7])                           // 2
//   Sort.shuffle([1, 2, 3, 4])                    // random order

class Sort()

// ── Internal helpers ─────────────────────────────────────────

function sortMergeTwo(a: Array<int>, b: Array<int>): Array<int> {
    let result: Array<int> = []
    let i = 0
    let j = 0
    let aLen = a.length()
    let bLen = b.length()
    while (i < aLen && j < bLen) {
        if (a[i] <= b[j]) {
            result = result.push(a[i])
            i++
        } else {
            result = result.push(b[j])
            j++
        }
    }
    while (i < aLen) {
        result = result.push(a[i])
        i++
    }
    while (j < bLen) {
        result = result.push(b[j])
        j++
    }
    return result
}

function sortInsert(arr: Array<int>, val: int): Array<int> {
    let result: Array<int> = []
    let inserted = 0
    let n = arr.length()
    for (let i = 0; i < n; i++) {
        if (inserted == 0 && val <= arr[i]) {
            result = result.push(val)
            inserted = 1
        }
        result = result.push(arr[i])
    }
    if (inserted == 0) {
        result = result.push(val)
    }
    return result
}

// ── Sorting algorithms ───────────────────────────────────────

// Quicksort — 3-way partition, O(n log n) average
function Sort_quickSort(arr: Array<int>): Array<int> {
    let n = arr.length()
    if (n <= 1) {
        return arr
    }
    let pivot = arr[n / 2]
    let less: Array<int> = []
    let equal: Array<int> = []
    let greater: Array<int> = []
    for (let i = 0; i < n; i++) {
        let val = arr[i]
        if (val < pivot) {
            less = less.push(val)
        } else if (val > pivot) {
            greater = greater.push(val)
        } else {
            equal = equal.push(val)
        }
    }
    let sortedLess = Sort_quickSort(less)
    let sortedGreater = Sort_quickSort(greater)
    return sortedLess.concat(equal).concat(sortedGreater)
}

// Merge sort — stable, guaranteed O(n log n)
function Sort_mergeSort(arr: Array<int>): Array<int> {
    let n = arr.length()
    if (n <= 1) {
        return arr
    }
    let mid = n / 2
    let left = arr.slice(0, mid)
    let right = arr.slice(mid, n)
    let sortedLeft = Sort_mergeSort(left)
    let sortedRight = Sort_mergeSort(right)
    return sortMergeTwo(sortedLeft, sortedRight)
}

// Insertion sort — O(n²), efficient for small or nearly-sorted arrays
function Sort_insertionSort(arr: Array<int>): Array<int> {
    let result: Array<int> = []
    let n = arr.length()
    for (let i = 0; i < n; i++) {
        result = sortInsert(result, arr[i])
    }
    return result
}

// ── Sorted-array utilities ───────────────────────────────────

// Check if array is sorted in ascending order
function Sort_isSorted(arr: Array<int>): int {
    let n = arr.length()
    for (let i = 1; i < n; i++) {
        if (arr[i] < arr[i - 1]) {
            return 0
        }
    }
    return 1
}

// Binary search in sorted array — returns index or -1 if not found
function Sort_binarySearch(arr: Array<int>, target: int): int {
    let lo = 0
    let hi = arr.length() - 1
    while (lo <= hi) {
        let mid = lo + (hi - lo) / 2
        let midVal = arr[mid]
        if (midVal == target) {
            return mid
        } else if (midVal < target) {
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return -1
}

// Remove adjacent duplicates from sorted array
function Sort_unique(arr: Array<int>): Array<int> {
    let n = arr.length()
    if (n <= 1) {
        return arr
    }
    let result: Array<int> = []
    result = result.push(arr[0])
    for (let i = 1; i < n; i++) {
        if (arr[i] != arr[i - 1]) {
            result = result.push(arr[i])
        }
    }
    return result
}

// Merge two sorted arrays into one sorted array
function Sort_merge(a: Array<int>, b: Array<int>): Array<int> {
    return sortMergeTwo(a, b)
}

// ── General utilities ────────────────────────────────────────

// Fisher-Yates shuffle — returns array in random order
function Sort_shuffle(arr: Array<int>): Array<int> {
    let n = arr.length()
    if (n <= 1) {
        return arr
    }
    let remaining = arr.slice(0, n)
    let result: Array<int> = []
    let rLen = n
    while (rLen > 0) {
        let idx = Math.randomInt(rLen)
        result = result.push(remaining[idx])
        let before = remaining.slice(0, idx)
        let after = remaining.slice(idx + 1, rLen)
        remaining = before.concat(after)
        rLen = rLen - 1
    }
    return result
}

// Minimum element (undefined behavior on empty array)
function Sort_min(arr: Array<int>): int {
    let n = arr.length()
    let result = arr[0]
    for (let i = 1; i < n; i++) {
        if (arr[i] < result) {
            result = arr[i]
        }
    }
    return result
}

// Maximum element (undefined behavior on empty array)
function Sort_max(arr: Array<int>): int {
    let n = arr.length()
    let result = arr[0]
    for (let i = 1; i < n; i++) {
        if (arr[i] > result) {
            result = arr[i]
        }
    }
    return result
}

// Sort in descending order
function Sort_descending(arr: Array<int>): Array<int> {
    let sorted = Sort_quickSort(arr)
    return sorted.reverse()
}
