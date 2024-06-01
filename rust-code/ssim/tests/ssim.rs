extern crate ssim;

use png;

use std::fs::File;

#[test]
fn test_ssim() {
    let decoder = png::Decoder::new(File::open("rust-code/ssim/tests/post.png").unwrap());
    let mut reader = decoder.read_info().unwrap();
    // Allocate the output buffer.
    let mut buf = vec![0; reader.output_buffer_size()];
    // Read the next frame. An APNG might contain multiple frames.
    let info = reader.next_frame(&mut buf).unwrap();
    // Grab the bytes of the image.
    let bytes = &buf[..info.buffer_size()];
    ssim::ssim();
    assert_eq!([255, 255, 255, 255], bytes[0..4]);
}
