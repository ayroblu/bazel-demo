use std::collections::HashMap;

use crate::http;
use crate::http::{register_http_provider, HttpError, HttpMethod, HttpRequest, HttpResponse};

uniffi::setup_scaffolding!();

#[uniffi::export(callback_interface)]
#[async_trait::async_trait]
pub trait HttpProvider: Send + Sync + 'static {
    async fn send_request(
        &self,
        request: UniffiHttpRequest,
    ) -> Result<UniffiHttpResponse, UniffiHttpError>;
}

#[uniffi::export]
pub fn set_http_provider(provider: Box<dyn HttpProvider>) {
    let http_provider = HttpProviderWrap { provider };
    register_http_provider(Box::new(http_provider));
}

pub struct HttpProviderWrap {
    provider: Box<dyn HttpProvider>,
}

#[async_trait::async_trait]
impl http::HttpProvider for HttpProviderWrap {
    async fn send_request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError> {
        let req: UniffiHttpRequest = request.into();
        let response = self.provider.send_request(req).await?;
        let res: HttpResponse = response.into();
        Ok(res)
    }
}

#[derive(uniffi::Record)]
#[uniffi(name = "HttpRequest")]
pub struct UniffiHttpRequest {
    pub url: String,
    pub method: UniffiHttpMethod,
    pub headers: Option<HashMap<String, String>>,
    pub body: Option<Vec<u8>>, // should be None for GET
}
impl From<HttpRequest> for UniffiHttpRequest {
    fn from(req: HttpRequest) -> Self {
        Self {
            url: req.url,
            method: req.method.into(),
            headers: req.headers,
            body: req.body,
        }
    }
}

#[derive(uniffi::Record)]
#[uniffi(name = "HttpResponse")]
pub struct UniffiHttpResponse {
    pub status_code: u16,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}
impl From<UniffiHttpResponse> for HttpResponse {
    fn from(res: UniffiHttpResponse) -> Self {
        Self {
            status_code: res.status_code,
            headers: res.headers,
            body: res.body,
        }
    }
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(name = "HttpError")]
pub enum UniffiHttpError {
    #[error("Response was not http")]
    NotHttp,
    #[error("Invalid url: {url}")]
    InvalidUrl { url: String },
    #[error("Network error: {0}")]
    NetworkError(String),
    #[error("Unknown error {0}")]
    Unknown(String),
}
impl From<UniffiHttpError> for HttpError {
    fn from(error: UniffiHttpError) -> Self {
        match error {
            UniffiHttpError::NotHttp => HttpError::NotHttp,
            UniffiHttpError::InvalidUrl { url } => HttpError::InvalidUrl { url },
            UniffiHttpError::NetworkError(s) => HttpError::NetworkError(s),
            UniffiHttpError::Unknown(s) => HttpError::Unknown(s),
        }
    }
}

#[derive(uniffi::Enum, Debug, PartialEq, Eq)]
#[uniffi(name = "HttpMethod")]
pub enum UniffiHttpMethod {
    Get,
    Post,
    Put,
    Patch,
    Head,
    Delete,
}
impl From<HttpMethod> for UniffiHttpMethod {
    fn from(method: HttpMethod) -> Self {
        match method {
            HttpMethod::Get => UniffiHttpMethod::Get,
            HttpMethod::Post => UniffiHttpMethod::Post,
            HttpMethod::Put => UniffiHttpMethod::Put,
            HttpMethod::Patch => UniffiHttpMethod::Patch,
            HttpMethod::Head => UniffiHttpMethod::Head,
            HttpMethod::Delete => UniffiHttpMethod::Delete,
        }
    }
}
impl From<UniffiHttpMethod> for HttpMethod {
    fn from(method: UniffiHttpMethod) -> Self {
        match method {
            UniffiHttpMethod::Get => HttpMethod::Get,
            UniffiHttpMethod::Post => HttpMethod::Post,
            UniffiHttpMethod::Put => HttpMethod::Put,
            UniffiHttpMethod::Patch => HttpMethod::Patch,
            UniffiHttpMethod::Head => HttpMethod::Head,
            UniffiHttpMethod::Delete => HttpMethod::Delete,
        }
    }
}
#[uniffi::export]
fn http_method_to_string(method: UniffiHttpMethod) -> String {
    return HttpMethod::from(method).to_string();
}
