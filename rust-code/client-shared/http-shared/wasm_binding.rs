use futures::channel::oneshot;
use js_sys::{Function, Promise};
use send_wrapper::SendWrapper;
use serde::{Deserialize, Serialize};
use serde_wasm_bindgen::{from_value, to_value};
use std::collections::{BTreeMap, HashMap};
use tsify::Tsify;
use wasm_bindgen::prelude::*;
use wasm_bindgen::JsCast;
use wasm_bindgen_futures::spawn_local;
use wasm_bindgen_futures::JsFuture;

use crate::http;
use crate::http::{register_http_provider, HttpError, HttpProvider};

#[wasm_bindgen(typescript_custom_section)]
const TS_APPEND: &'static str = r#"
export type HttpProvider = (request: HttpRequest) => Promise<HttpResponse>;"#;

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(typescript_type = "HttpProvider")]
    pub type HttpProviderType;
}
#[wasm_bindgen(js_name = "setHttpProvider")]
pub fn set_http_provider(provider: HttpProviderType) {
    let provider_fn: Function = provider.unchecked_into();
    let fetch_provider = Fetch {
        func: SendWrapper::new(provider_fn),
    };

    register_http_provider(Box::new(fetch_provider));
}

pub struct Fetch {
    func: SendWrapper<Function>,
}

#[async_trait::async_trait]
impl HttpProvider for Fetch {
    async fn send_request(
        &self,
        request: http::HttpRequest,
    ) -> Result<http::HttpResponse, http::HttpError> {
        let (tx, rx) = oneshot::channel();
        let func = self.func.clone();

        spawn_local(async move {
            let result = async {
                let wasm_req: HttpRequest = request.into();
                let js_req = to_value(&wasm_req).map_err(|e| {
                    HttpError::Unknown("Serialization: ".to_owned() + &e.to_string())
                })?;
                let promise_val = func
                    .call1(&JsValue::NULL, &js_req)
                    .map_err(|e| HttpError::Unknown(format!("JsError {:?}", e)))?;
                let promise = promise_val
                    .dyn_into::<Promise>()
                    .map_err(|e| HttpError::Unknown(format!("Not a promise {:?}", e)))?;
                let js_res = JsFuture::from(promise)
                    .await
                    .map_err(|e| HttpError::Unknown(format!("NetworkError {:?}", e)))?;
                let response: HttpResponse = from_value(js_res).map_err(|e| {
                    HttpError::Unknown("Deserialization: ".to_owned() + &e.to_string())
                })?;
                Ok(response.into())
            }
            .await;

            let _ = tx.send(result);
        });

        rx.await
            .map_err(|e| HttpError::Unknown(format!("canceled {:?}", e)))?
    }
}

#[derive(Tsify, Serialize, Deserialize)]
#[tsify(into_wasm_abi, from_wasm_abi)]
pub struct HttpRequest {
    pub url: String,
    pub method: HttpMethod,
    pub headers: Option<HashMap<String, String>>,
    pub body: Option<Vec<u8>>, // should be None for GET
}
impl From<http::HttpRequest> for HttpRequest {
    fn from(req: http::HttpRequest) -> Self {
        Self {
            url: req.url,
            method: req.method.into(),
            headers: req.headers.map(|h| HashMap::from_iter(h)),
            body: req.body,
        }
    }
}

#[derive(Tsify, Serialize, Deserialize)]
#[tsify(into_wasm_abi, from_wasm_abi)]
#[serde(rename_all = "camelCase")]
pub struct HttpResponse {
    pub status_code: u16,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}
impl From<HttpResponse> for http::HttpResponse {
    fn from(res: HttpResponse) -> Self {
        Self {
            status_code: res.status_code,
            headers: BTreeMap::from_iter(res.headers),
            body: res.body,
        }
    }
}

// #[derive(Debug, thiserror::Error)]
// pub enum WasmHttpError {
//     #[error("Response was not http")]
//     NotHttp,
//     #[error("Invalid url: {url}")]
//     InvalidUrl { url: String },
//     #[error("Network error: {0}")]
//     NetworkError(String),
//     #[error("Unknown error {0}")]
//     Unknown(String),
// }

// // Useful to output back to JS if needed
// impl From<WasmHttpError> for JsValue {
//     fn from(error: WasmHttpError) -> Self {
//         let js_error = js_sys::Error::new(&error.to_string());
//         js_error.set_name("HttpError");
//         js_error.into()
//     }
// }

#[derive(Tsify, Serialize, Deserialize)]
#[tsify(into_wasm_abi, from_wasm_abi)]
#[derive(Debug, PartialEq, Eq)]
#[serde(rename_all = "UPPERCASE")]
pub enum HttpMethod {
    Get,
    Post,
    Put,
    Patch,
    Head,
    Delete,
}
impl From<http::HttpMethod> for HttpMethod {
    fn from(method: http::HttpMethod) -> Self {
        match method {
            http::HttpMethod::Get => HttpMethod::Get,
            http::HttpMethod::Post => HttpMethod::Post,
            http::HttpMethod::Put => HttpMethod::Put,
            http::HttpMethod::Patch => HttpMethod::Patch,
            http::HttpMethod::Head => HttpMethod::Head,
            http::HttpMethod::Delete => HttpMethod::Delete,
        }
    }
}
// pub fn http_method_to_string(method: HttpMethod) -> String {
//     return method.to_string();
// }
