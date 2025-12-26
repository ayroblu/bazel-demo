extern crate logger;

use crate::http::{HttpError, HttpRequest, HttpRequestOptions, HttpResponse, GLOBAL_HTTP_PROVIDER};
use logger::*;
use std::sync::LazyLock;
use std::time::Instant;

pub trait HttpFilter: Send + Sync {
    async fn handle(&self, request: HttpRequest) -> Result<HttpResponse, HttpError>;
}

pub struct LoggingFilter<H> {
    handler: H,
}

impl<H: HttpFilter> HttpFilter for LoggingFilter<H> {
    async fn handle(&self, req: HttpRequest) -> Result<HttpResponse, HttpError> {
        if req.options.contains(HttpRequestOptions::SKIP_LOG) {
            return self.handler.handle(req).await;
        }
        let start = Instant::now();

        let method = req.method.clone();
        let url = req.url.clone();

        log!("{} {}", req.method, req.url);
        let result = self.handler.handle(req).await;

        let duration_ms = start.elapsed().as_millis();

        match &result {
            Ok(resp) => log!(
                "HTTP-{} +{}ms {} {}",
                resp.status_code,
                duration_ms,
                method,
                url
            ),
            Err(err) => log!("{} +{}ms {} {}", err, duration_ms, method, url),
        }
        result
    }
}

pub struct RequestFilter;

impl HttpFilter for RequestFilter {
    async fn handle(&self, req: HttpRequest) -> Result<HttpResponse, HttpError> {
        let Some(http) = GLOBAL_HTTP_PROVIDER.get() else {
            return Err(HttpError::NoProvider);
        };
        return http.send_request(req).await;
    }
}

/// Essentially
/// LoggingFilter {
///     handler: RequestFilter,
/// }
#[macro_export]
macro_rules! compose_filters {
    ($last:expr) => {
        $last
    };
    ($head:ident, $($tail:tt)*) => {
        $head {
            handler: compose_filters!($($tail)*),
        }
    };
}

type DefaultFilters = LoggingFilter<RequestFilter>;
pub static DEFAULT_FILTERS: LazyLock<DefaultFilters> =
    LazyLock::new(|| compose_filters!(LoggingFilter, RequestFilter));
