#![no_std]
#![no_main]

use core::arch::asm;
use core::panic::PanicInfo;

const OS_WRITE0: usize = 2;
const OS_NEW_LINE: usize = 3;

unsafe extern "C" {
    fn _Exit(status: i32) -> !;
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

#[inline(never)]
fn checked_index(values: &[usize], index: usize) -> usize {
    values[index]
}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 {
    let values = [10usize, 20, 30];
    let value = checked_index(&values, 1);

    if value == 20 {
        os_write0(c"Hello world".as_ptr().cast::<u8>());
        os_new_line();
    }

    0
}

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    unsafe { _Exit(1) }
}
