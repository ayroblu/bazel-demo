extern crate ssim;

use png;
use ssim::RgbaImage;

use std::fs::File;

#[test]
fn test_ssim() {
    let image = read_png("rust-code/ssim/tests/post.png");
    let image2 = read_png("rust-code/ssim/tests/post-2.png");
    let expected_diff_image = read_png("rust-code/ssim/tests/diff-post.png");
    let actual_diff_image = ssim::ssim(image, image2).unwrap_err();
    assert_eq!(expected_diff_image, actual_diff_image.image);
}

#[test]
fn test_ssim_same() {
    let image = read_png("rust-code/ssim/tests/post.png");
    let result = ssim::ssim(image.clone(), image.clone());
    assert!(result.is_ok());
}

fn read_png(file_name: &str) -> RgbaImage {
    let decoder = png::Decoder::new(File::open(file_name).unwrap());
    let mut reader = decoder.read_info().unwrap();
    let mut buf = vec![0; reader.output_buffer_size()];
    // Read the next frame. An APNG might contain multiple frames.
    let info = reader.next_frame(&mut buf).unwrap();

    RgbaImage {
        width: info.width as usize,
        height: info.height as usize,
        buf,
    }
}
