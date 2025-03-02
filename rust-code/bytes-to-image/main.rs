use png;
use std::fs::File;
use std::io::BufWriter;
use std::path::Path;

fn main() {
    let path = Path::new(r"image.png");
    let file = File::create(path).unwrap();
    let ref mut w = BufWriter::new(file);

    let mut encoder = png::Encoder::new(w, 488, 136);
    // let mut encoder = png::Encoder::new(w, 136, 136);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.set_source_gamma(png::ScaledFloat::from_scaled(45455)); // 1.0 / 2.2, scaled by 100000
    encoder.set_source_gamma(png::ScaledFloat::new(1.0 / 2.2)); // 1.0 / 2.2, unscaled, but rounded
    let source_chromaticities = png::SourceChromaticities::new(
        // Using unscaled instantiation here
        (0.31270, 0.32900),
        (0.64000, 0.33000),
        (0.30000, 0.60000),
        (0.15000, 0.06000),
    );
    encoder.set_source_chromaticities(source_chromaticities);
    let mut writer = encoder.write_header().unwrap();

    let data = image(TEXT3_2);
    writer.write_image_data(&data).unwrap(); // Save
    println!("Saved!");
}

fn image(text: &str) -> Vec<u8> {
    let bool_vec = hex_string_to_bool_vec(text);
    bool_vec
        .iter()
        .flat_map(|&v| {
            if v {
                [255, 255, 255, 255]
            } else {
                [0, 0, 0, 255]
            }
        })
        .collect()
}
fn hex_string_to_bool_vec(hex_string: &str) -> Vec<bool> {
    let cleaned = hex_string.replace("\n", "").replace(" ", "");

    let mut result = Vec::new();
    let mut i = 0;
    while i < cleaned.len() {
        if i + 2 <= cleaned.len() {
            let byte_str = &cleaned[i..i + 2];
            if let Ok(byte) = u8::from_str_radix(byte_str, 16) {
                for j in 0..8 {
                    let bit = (byte >> j) & 1;
                    result.push(bit == 1);
                }
            } else {
                eprintln!("Invalid hex characters: {}", byte_str);
            }
        }
        i += 2;
    }
    // for c in cleaned_hex.chars() {
    //     if let Some(digit) = c.to_digit(16) {
    //         for i in (0..4) {
    //             let bit = (digit >> i) & 1;
    //             result.push(bit == 1);
    //         }
    //     }
    // }

    result
}
const TEXT2: &str = "";

const TEXT2_2: &str = "";

const TEXT3: &str = "";

const TEXT3_2: &str = "";
