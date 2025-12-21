use std::sync::OnceLock;
use std::{collections::HashMap, sync::Arc};

uniffi::setup_scaffolding!();

#[uniffi::export(callback_interface)]
#[async_trait::async_trait]
pub trait HttpProvider: Send + Sync + 'static {
    async fn send_request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError>;
}

pub static GLOBAL_HTTP_PROVIDER: OnceLock<Arc<dyn HttpProvider>> = OnceLock::new();

#[uniffi::export]
pub fn register_http_provider(provider: Box<dyn HttpProvider>) {
    GLOBAL_HTTP_PROVIDER.get_or_init(|| Arc::from(provider));
}

#[derive(uniffi::Record)]
pub struct HttpRequest {
    pub url: String,
    pub method: HttpMethod,
    pub headers: Option<HashMap<String, String>>,
    pub body: Option<Vec<u8>>, // should be None for GET
}

#[derive(uniffi::Record)]
pub struct HttpResponse {
    pub status_code: u16,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum HttpError {
    #[error("Response was not http")]
    NotHttp,
    #[error("Invalid url: {url}")]
    InvalidUrl { url: String },
    #[error("Unknown error")]
    Unknown,
}

#[derive(Debug, PartialEq, Eq, uniffi::Enum)]
pub enum HttpMethod {
    Get,
    Post,
    Put,
    Patch,
    Head,
    Delete,
}
impl std::fmt::Display for HttpMethod {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            Self::Get => "GET",
            Self::Post => "POST",
            Self::Put => "PUT",
            Self::Patch => "PATCH",
            Self::Head => "HEAD",
            Self::Delete => "DELETE",
        };
        write!(f, "{}", s)
    }
}
#[uniffi::export]
fn http_method_to_string(method: HttpMethod) -> String {
    return method.to_string();
}
