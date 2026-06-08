#![no_std]

#[inline(never)]
pub fn checked_index(values: &[usize], index: usize) -> usize {
    values[index]
}

#[inline(never)]
pub fn probe() -> usize {
    let values = [1usize, 2, 3, 4];
    checked_index(&values, 2)
}

