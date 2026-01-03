extern crate http_shared_lib;
extern crate logger;

use http_shared_lib::http::send_request;
use http_shared_lib::http::HttpMethod;
use http_shared_lib::http::HttpRequest;
use http_shared_lib::http::HttpRequestOptions;
use logger::*;
use std::sync::Arc;

uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn print_and_add(a: i32, b: i32) -> i32 {
    log!("Hello, World!");
    a + b
}

#[uniffi::export]
pub fn subber(thing: Box<dyn ClosureCallback>) -> Arc<Cleanup> {
    thing.notif();
    return Arc::new(Cleanup {});
}

#[uniffi::export(callback_interface)]
pub trait ClosureCallback: Send + Sync + 'static {
    // notify is a reserved word in kotlin 🤦
    fn notif(&self);
}

#[derive(uniffi::Object)]
pub struct Cleanup;
#[uniffi::export]
impl Cleanup {
    fn dispose(&self) {
        log!("dispose!");
    }
}

#[uniffi::export]
pub async fn check_network() -> Option<String> {
    let result = send_request(HttpRequest {
        url: "https://api.ipify.org".to_string(),
        method: HttpMethod::Get,
        headers: None,
        body: None,
        options: HttpRequestOptions(0),
    })
    .await;
    match &*result {
        Ok(response) => {
            let ip = String::from_utf8_lossy(&response.body);
            log!("{}", ip);
            return Some(ip.to_string());
        }
        Err(err) => elog!("err: {}", err),
    };
    return None;
}
