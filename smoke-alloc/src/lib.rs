#![no_std]
#![no_main]

extern crate alloc;

use alloc::boxed::Box;
use alloc::string::String;
use alloc::vec::Vec;
use core::alloc::{GlobalAlloc, Layout};
use core::arch::asm;
use core::cmp;
use core::mem;
use core::panic::PanicInfo;
use core::ptr;
use core::sync::atomic::{AtomicUsize, Ordering};

const OS_WRITE0: usize = 2;
const OS_NEW_LINE: usize = 3;
const MALLOC_ALIGNMENT: usize = 16;
const HEADER_WORDS: usize = 2;
const HEADER_SIZE: usize = HEADER_WORDS * mem::size_of::<usize>();
static REALLOCATIONS: AtomicUsize = AtomicUsize::new(0);

unsafe extern "C" {
    fn malloc(size: usize) -> *mut u8;
    fn free(ptr: *mut u8);
    fn realloc(ptr: *mut u8, size: usize) -> *mut u8;
    fn _Exit(status: i32) -> !;
}

struct MallocAllocator;

#[global_allocator]
static GLOBAL_ALLOCATOR: MallocAllocator = MallocAllocator;

#[unsafe(export_name = "_RNvCs6BVCBk4oTa3_7___rustc35___rust_no_alloc_shim_is_unstable_v2")]
pub extern "C" fn rust_no_alloc_shim_is_unstable_v2() {}

#[unsafe(export_name = "_RNvCs6BVCBk4oTa3_7___rustc26___rust_alloc_error_handler")]
pub extern "C" fn rust_alloc_error_handler(_size: usize, _align: usize) -> ! {
    unsafe { _Exit(2) }
}

#[repr(C)]
struct AllocationHeader {
    original: *mut u8,
}

fn align_up(value: usize, alignment: usize) -> Option<usize> {
    let mask = alignment.checked_sub(1)?;
    value.checked_add(mask).map(|v| v & !mask)
}

unsafe fn store_header(aligned_ptr: *mut u8, original_ptr: *mut u8) {
    let header_ptr = unsafe { aligned_ptr.cast::<AllocationHeader>().sub(1) };

    unsafe {
        ptr::write(
            header_ptr,
            AllocationHeader {
                original: original_ptr,
            },
        );
    }
}

unsafe fn load_header(ptr: *mut u8) -> AllocationHeader {
    unsafe { ptr.cast::<AllocationHeader>().sub(1).read() }
}

fn uses_native_alignment(layout: Layout) -> bool {
    layout.align() <= MALLOC_ALIGNMENT
}

unsafe fn allocate_aligned(layout: Layout) -> *mut u8 {
    let padded = match layout
        .size()
        .checked_add(layout.align())
        .and_then(|size| size.checked_add(HEADER_SIZE))
    {
        Some(size) => size,
        None => return ptr::null_mut(),
    };

    let original = unsafe { malloc(padded) };
    if original.is_null() {
        return ptr::null_mut();
    }

    let aligned = match align_up(original as usize + HEADER_SIZE, layout.align()) {
        Some(value) => value as *mut u8,
        None => {
            unsafe { free(original) };
            return ptr::null_mut();
        }
    };

    unsafe { store_header(aligned, original) };

    aligned
}

unsafe fn deallocate_aligned(ptr: *mut u8) {
    let header = unsafe { load_header(ptr) };
    unsafe { free(header.original) };
}

unsafe fn reallocate_aligned(ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
    let new_layout = match Layout::from_size_align(new_size, layout.align()) {
        Ok(layout) => layout,
        Err(_) => return ptr::null_mut(),
    };
    let new_ptr = unsafe { allocate_aligned(new_layout) };

    if new_ptr.is_null() {
        return ptr::null_mut();
    }

    unsafe {
        ptr::copy_nonoverlapping(ptr, new_ptr, cmp::min(layout.size(), new_size));
        deallocate_aligned(ptr);
    }

    new_ptr
}

unsafe impl GlobalAlloc for MallocAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if uses_native_alignment(layout) {
            unsafe { malloc(layout.size()) }
        } else {
            unsafe { allocate_aligned(layout) }
        }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        if uses_native_alignment(layout) {
            unsafe { free(ptr) };
        } else {
            unsafe { deallocate_aligned(ptr) };
        }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        REALLOCATIONS.fetch_add(1, Ordering::Relaxed);

        if uses_native_alignment(layout) {
            unsafe { realloc(ptr, new_size) }
        } else {
            unsafe { reallocate_aligned(ptr, layout, new_size) }
        }
    }
}

#[inline]
unsafe fn swi1(number: usize, arg0: usize) -> usize {
    let result: usize;

    unsafe {
        asm!(
            "svc 0",
            in("x10") number,
            in("x0") arg0,
            lateout("x0") result,
            options(nostack)
        );
    }

    result
}

#[inline]
fn os_write0(message: *const u8) {
    unsafe {
        let _ = swi1(OS_WRITE0, message as usize);
    }
}

#[inline]
fn os_new_line() {
    unsafe {
        let _ = swi1(OS_NEW_LINE, 0);
    }
}

#[repr(align(64))]
struct OverAligned([u8; 33]);

#[inline(never)]
fn smoke_alloc() -> bool {
    let boxed = Box::new(OverAligned([0x5a; 33]));
    if boxed.0[0] != 0x5a {
        return false;
    }

    let mut numbers = Vec::with_capacity(1);
    let initial_capacity = numbers.capacity();
    for value in 0..32u32 {
        numbers.push(value);
    }
    if numbers.len() != 32 || numbers[31] != 31 || numbers.capacity() <= initial_capacity {
        return false;
    }

    let mut text = String::from("alloc");
    text.push(' ');
    text.push_str("ready");
    if text.as_str() != "alloc ready" {
        return false;
    }

    REALLOCATIONS.load(Ordering::Relaxed) > 0
}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 {
    if smoke_alloc() {
        os_write0(c"alloc smoke ok".as_ptr().cast::<u8>());
        os_new_line();
        0
    } else {
        1
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    unsafe { _Exit(1) }
}
