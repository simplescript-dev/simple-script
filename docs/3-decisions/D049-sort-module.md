# D049: Sort Module — Sorting Algorithms & Utilities

**Status:** Accepted
**Depends on:** D043 (Math.randomInt for shuffle)

## Decision

Add `lib/sort.ss` — a pure SS standard library module providing sorting algorithms and sorted-array utilities for `Array<int>`.

## Reasoning

The builtin `.sort()` uses C `qsort` with i64 ascending comparison — no algorithm choice, no utilities. A Sort module fills gaps:

1. **Multiple algorithms** — quickSort (avg O(n log n)), mergeSort (stable, guaranteed O(n log n)), insertionSort (O(n²), good for small/nearly-sorted)
2. **Sorted-array utilities** — binarySearch, isSorted, unique, merge
3. **General utilities** — shuffle (Fisher-Yates), min, max, descending

## Rejected Alternatives

- **Custom comparator support**: Requires first-class function-as-parameter for sort, complex closure mechanics. Deferred.
- **String sorting**: Both `Array<int>` and `Array<string>` are `ptr` at LLVM level — can't overload on element type. Name-differentiated string methods possible but deferred.
- **HeapSort/BubbleSort**: Don't translate well to functional style (SS's `arr.push()` returns new array). QuickSort + MergeSort + InsertionSort cover the spectrum.

## Interfaces

### Import
```
import { Sort } from "@/lib/sort"
```

### Static Methods (11)

**Sorting algorithms** (return new sorted array):
- `Sort.quickSort(arr: Array<int>): Array<int>` — 3-way partition quicksort
- `Sort.mergeSort(arr: Array<int>): Array<int>` — recursive merge sort (stable)
- `Sort.insertionSort(arr: Array<int>): Array<int>` — functional insertion sort

**Sorted-array utilities**:
- `Sort.isSorted(arr: Array<int>): int` — 1 if ascending, 0 otherwise
- `Sort.binarySearch(arr: Array<int>, target: int): int` — index or -1
- `Sort.unique(arr: Array<int>): Array<int>` — remove adjacent duplicates (input must be sorted)
- `Sort.merge(a: Array<int>, b: Array<int>): Array<int>` — merge two sorted arrays

**General utilities**:
- `Sort.shuffle(arr: Array<int>): Array<int>` — Fisher-Yates randomization
- `Sort.min(arr: Array<int>): int` — minimum element
- `Sort.max(arr: Array<int>): int` — maximum element
- `Sort.descending(arr: Array<int>): Array<int>` — sort descending

### Internal Helpers (1)
- `sortInsert(arr, val)` — insert value into sorted position

## Tensions

- **Functional style vs performance**: SS's `arr.push()` returns new arrays, so all algorithms create new arrays rather than sorting in-place. Acceptable for stdlib — users needing raw performance can use the builtin `.sort()`.
- **Int-only**: Array element type not distinguishable at overload level. String sorting deferred.
