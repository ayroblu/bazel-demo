use std::any::Any;
use std::collections::HashMap;
use std::time::Instant;

// --- 1. Define the heterogeneous data types ---

#[derive(Debug, Clone)]
struct U32Data(u32);

#[derive(Debug, Clone)]
struct StringData(String);

// --- 2. Define the Static/Enum approach (The high-performance choice) ---

// A single enum variant that covers all possible types we want to store.
// Since the types are known, the compiler can use static dispatch and optimize heavily.
#[derive(Debug)]
enum Data {
    Integer(U32Data),
    Text(StringData),
}

// --- 3. Define the two benchmark functions ---

const MAP_SIZE: u32 = 100_000;
const ITERATIONS: u32 = 10;

/// Fills the HashMap with Box<dyn Any> values.
fn populate_any_map() -> HashMap<u32, Box<dyn Any>> {
    let mut map: HashMap<u32, Box<dyn Any>> = HashMap::new();
    for i in 0..MAP_SIZE {
        if i % 2 == 0 {
            // Store U32Data (even keys)
            map.insert(i, Box::new(U32Data(i)));
        } else {
            // Store StringData (odd keys)
            map.insert(i, Box::new(StringData(format!("value_{}", i))));
        }
    }
    map
}

/// Fills the HashMap with Enum values.
fn populate_enum_map() -> HashMap<u32, Data> {
    let mut map: HashMap<u32, Data> = HashMap::new();
    for i in 0..MAP_SIZE {
        if i % 2 == 0 {
            // Store Integer variant (even keys)
            map.insert(i, Data::Integer(U32Data(i)));
        } else {
            // Store Text variant (odd keys)
            map.insert(i, Data::Text(StringData(format!("value_{}", i))));
        }
    }
    map
}

/// Benchmarks the retrieval and processing of values from the Box<dyn Any> map.
/// This involves the costly 'downcasting' at runtime.
fn benchmark_any(map: &HashMap<u32, Box<dyn Any>>) {
    let start = Instant::now();
    let mut total_result = 0_u128; // Dummy variable to ensure the loop isn't optimized away

    for _ in 0..ITERATIONS {
        for i in 0..MAP_SIZE {
            if let Some(any_box) = map.get(&i) {
                // *** Dynamic Dispatch & Downcasting Overhead: ***
                // 1. Runtime vtable lookup to find the downcast method.
                // 2. Runtime type ID comparison.
                if i % 2 == 0 {
                    // Try to downcast to U32Data
                    if let Some(data) = any_box.downcast_ref::<U32Data>() {
                        total_result += (data.0 as u128) * 2; // Simple operation
                    }
                } else {
                    // Try to downcast to StringData
                    if let Some(data) = any_box.downcast_ref::<StringData>() {
                        total_result += data.0.len() as u128; // Simple operation
                    }
                }
            }
        }
    }

    let duration = start.elapsed();
    println!("--- Type-Erased (Box<dyn Any>) ---");
    println!("Total time ({} iterations): {:?}", ITERATIONS, duration);
    println!("Average time: {:?}", duration / ITERATIONS);
    // Print the dummy result to prevent optimization
    println!("(Total Result: {})", total_result);
}

/// Benchmarks the retrieval and processing of values from the Enum map.
/// This uses highly optimized static dispatch via 'match'.
fn benchmark_enum(map: &HashMap<u32, Data>) {
    let start = Instant::now();
    let mut total_result = 0_u128; // Dummy variable to ensure the loop isn't optimized away

    for _ in 0..ITERATIONS {
        for i in 0..MAP_SIZE {
            if let Some(data_enum) = map.get(&i) {
                // *** Static Dispatch via Match: ***
                // 1. Direct memory access.
                // 2. Compiler generates a highly efficient jump table.
                match data_enum {
                    Data::Integer(data) => {
                        total_result += (data.0 as u128) * 2; // Simple operation
                    }
                    Data::Text(data) => {
                        total_result += data.0.len() as u128; // Simple operation
                    }
                }
            }
        }
    }

    let duration = start.elapsed();
    println!("\n--- Static Dispatch (Enum) ---");
    println!("Total time ({} iterations): {:?}", ITERATIONS, duration);
    println!("Average time: {:?}", duration / ITERATIONS);
    // Print the dummy result to prevent optimization
    println!("(Total Result: {})", total_result);
}

fn main() {
    println!("--- Populating Maps ({} entries each) ---", MAP_SIZE);

    let start_any = Instant::now();
    let any_map = populate_any_map();
    println!("Any Map Population Time: {:?}", start_any.elapsed());

    let start_enum = Instant::now();
    let enum_map = populate_enum_map();
    println!("Enum Map Population Time: {:?}", start_enum.elapsed());

    println!(
        "\n--- Starting Benchmarks (Iterating {} times) ---",
        ITERATIONS
    );

    // Run the benchmarks
    benchmark_any(&any_map);
    benchmark_enum(&enum_map);

    println!("\nNote: The Enum approach should be significantly faster due to static dispatch and the lack of runtime downcasting overhead.");
}
