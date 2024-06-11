use std::cmp::max;

pub fn ssim(actual: RgbaImage, expected: RgbaImage) -> Result<bool, DiffImage> {
    let max_width = max(actual.width, expected.width);
    let max_height = max(actual.height, expected.height);
    let num_bytes: usize = max_width * max_height * 4;
    let mut buf = vec![0; num_bytes];
    // Ok(true)
    Err(DiffImage {
        image: RgbaImage {
            width: max_width,
            height: max_height,
            buf,
        },
        diff: 0.01,
    })
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub struct RgbaImage {
    pub width: usize,
    pub height: usize,
    // pub bytes: &'a [u8],
    pub buf: Vec<u8>,
}

pub struct DiffImage {
    pub image: RgbaImage,
    pub diff: f64,
}
