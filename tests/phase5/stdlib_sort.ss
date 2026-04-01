// Test: Sort standard library module (D049)

import { Sort } from "@/lib/sort"

function main() {
    // ── quickSort ────────────────────────────────────────────
    let arr = [5, 3, 8, 1, 9, 2, 7, 4, 6]
    let sorted = Sort.quickSort(arr)
    if (sorted[0] != 1) { exit(1) }
    if (sorted[1] != 2) { exit(1) }
    if (sorted[2] != 3) { exit(1) }
    if (sorted[8] != 9) { exit(1) }
    if (sorted.length() != 9) { exit(1) }

    // ── mergeSort ────────────────────────────────────────────
    let sorted2 = Sort.mergeSort(arr)
    if (sorted2[0] != 1) { exit(1) }
    if (sorted2[4] != 5) { exit(1) }
    if (sorted2[8] != 9) { exit(1) }

    // ── insertionSort ────────────────────────────────────────
    let sorted3 = Sort.insertionSort(arr)
    if (sorted3[0] != 1) { exit(1) }
    if (sorted3[4] != 5) { exit(1) }
    if (sorted3[8] != 9) { exit(1) }

    // ── All algorithms agree ─────────────────────────────────
    for (let i = 0; i < 9; i++) {
        if (sorted[i] != sorted2[i]) { exit(1) }
        if (sorted[i] != sorted3[i]) { exit(1) }
    }

    // ── isSorted ─────────────────────────────────────────────
    if (Sort.isSorted(sorted) != 1) { exit(1) }
    if (Sort.isSorted(arr) != 0) { exit(1) }
    let single = [42]
    if (Sort.isSorted(single) != 1) { exit(1) }
    let empty: Array<int> = []
    if (Sort.isSorted(empty) != 1) { exit(1) }

    // ── binarySearch ─────────────────────────────────────────
    if (Sort.binarySearch(sorted, 1) != 0) { exit(1) }
    if (Sort.binarySearch(sorted, 5) != 4) { exit(1) }
    if (Sort.binarySearch(sorted, 9) != 8) { exit(1) }
    if (Sort.binarySearch(sorted, 10) != -1) { exit(1) }
    if (Sort.binarySearch(sorted, 0) != -1) { exit(1) }

    // ── unique ───────────────────────────────────────────────
    let dups = [1, 1, 2, 3, 3, 3, 4, 5, 5]
    let uniq = Sort.unique(dups)
    if (uniq.length() != 5) { exit(1) }
    if (uniq[0] != 1) { exit(1) }
    if (uniq[1] != 2) { exit(1) }
    if (uniq[2] != 3) { exit(1) }
    if (uniq[3] != 4) { exit(1) }
    if (uniq[4] != 5) { exit(1) }

    // ── merge ────────────────────────────────────────────────
    let a = [1, 3, 5, 7]
    let b = [2, 4, 6, 8]
    let merged = Sort.merge(a, b)
    if (merged.length() != 8) { exit(1) }
    for (let i = 0; i < 8; i++) {
        if (merged[i] != i + 1) { exit(1) }
    }

    // merge with empty
    let mergedA = Sort.merge(a, empty)
    if (mergedA.length() != 4) { exit(1) }
    let mergedB = Sort.merge(empty, b)
    if (mergedB.length() != 4) { exit(1) }

    // ── min / max ────────────────────────────────────────────
    if (Sort.min(arr) != 1) { exit(1) }
    if (Sort.max(arr) != 9) { exit(1) }
    if (Sort.min(single) != 42) { exit(1) }
    if (Sort.max(single) != 42) { exit(1) }

    // ── descending ───────────────────────────────────────────
    let desc = Sort.descending(arr)
    if (desc[0] != 9) { exit(1) }
    if (desc[1] != 8) { exit(1) }
    if (desc[8] != 1) { exit(1) }

    // ── shuffle ──────────────────────────────────────────────
    let small = [1, 2, 3, 4, 5]
    let shuffled = Sort.shuffle(small)
    if (shuffled.length() != 5) { exit(1) }
    // Verify shuffle contains same elements (sort and compare)
    let resorted = Sort.quickSort(shuffled)
    for (let i = 0; i < 5; i++) {
        if (resorted[i] != i + 1) { exit(1) }
    }

    // ── Edge cases ───────────────────────────────────────────
    // Empty array
    let emptySort = Sort.quickSort(empty)
    if (emptySort.length() != 0) { exit(1) }
    let emptyMerge = Sort.mergeSort(empty)
    if (emptyMerge.length() != 0) { exit(1) }
    let emptyInsert = Sort.insertionSort(empty)
    if (emptyInsert.length() != 0) { exit(1) }

    // Single element
    let singleSort = Sort.quickSort(single)
    if (singleSort[0] != 42) { exit(1) }

    // Already sorted
    let already = [1, 2, 3, 4, 5]
    let resorted2 = Sort.mergeSort(already)
    for (let i = 0; i < 5; i++) {
        if (resorted2[i] != i + 1) { exit(1) }
    }

    // With duplicates
    let withDups = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]
    let sortedDups = Sort.quickSort(withDups)
    if (sortedDups[0] != 1) { exit(1) }
    if (sortedDups[1] != 1) { exit(1) }
    if (sortedDups[10] != 9) { exit(1) }

    // Reverse sorted
    let rev = [5, 4, 3, 2, 1]
    let sortedRev = Sort.insertionSort(rev)
    for (let i = 0; i < 5; i++) {
        if (sortedRev[i] != i + 1) { exit(1) }
    }

    // Two elements
    let two = [2, 1]
    let sortedTwo = Sort.quickSort(two)
    if (sortedTwo[0] != 1) { exit(1) }
    if (sortedTwo[1] != 2) { exit(1) }

    println("All sort tests passed")
}
