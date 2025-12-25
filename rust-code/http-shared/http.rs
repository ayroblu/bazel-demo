use std::sync::OnceLock;
use std::{collections::HashMap, sync::Arc};

#[async_trait::async_trait]
pub trait HttpProvider: Send + Sync + 'static {
    async fn send_request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError>;
}

pub static GLOBAL_HTTP_PROVIDER: OnceLock<Arc<dyn HttpProvider>> = OnceLock::new();

pub fn register_http_provider(provider: Box<dyn HttpProvider>) {
    GLOBAL_HTTP_PROVIDER.get_or_init(|| Arc::from(provider));
}

pub struct HttpRequest {
    pub url: String,
    pub method: HttpMethod,
    pub headers: Option<HashMap<String, String>>,
    pub body: Option<Vec<u8>>, // should be None for GET
}

pub struct HttpResponse {
    pub status_code: u16,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}

#[derive(Debug, thiserror::Error)]
pub enum HttpError {
    #[error("Response was not http")]
    NotHttp,
    #[error("Invalid url: {url}")]
    InvalidUrl { url: String },
    #[error("Network error: {0}")]
    NetworkError(String),
    #[error("Unknown error {0}")]
    Unknown(String),
}

#[derive(Debug, PartialEq, Eq)]
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
