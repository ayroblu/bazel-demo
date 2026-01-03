extern crate logger;

use crate::http::{
    HttpError, HttpMethod, HttpRequest, HttpRequestOptions, HttpResponse, GLOBAL_HTTP_PROVIDER,
};
use dashmap::DashMap;
use logger::*;
use std::sync::{Arc, LazyLock};
use std::time::Instant;
use tokio::sync::OnceCell;

pub trait HttpFilter<R = Result<HttpResponse, HttpError>>: Send + Sync {
    async fn handle(&self, request: HttpRequest) -> R;
}

pub struct LoggingFilter<H> {
    handler: H,
}
impl<H: HttpFilter> LoggingFilter<H> {
    fn new(handler: H) -> Self {
        Self { handler }
    }
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

pub struct SingleGetFilter<H> {
    handler: H,
    cache: Arc<DashMap<HttpRequest, Arc<OnceCell<Arc<Result<HttpResponse, HttpError>>>>>>,
}
impl<H: HttpFilter> SingleGetFilter<H> {
    fn new(handler: H) -> Self {
        Self {
            handler,
            cache: Arc::new(DashMap::new()),
        }
    }
}

impl<H: HttpFilter> HttpFilter<Arc<Result<HttpResponse, HttpError>>> for SingleGetFilter<H> {
    async fn handle(&self, req: HttpRequest) -> Arc<Result<HttpResponse, HttpError>> {
        if req.method != HttpMethod::Get {
            let result = self.handler.handle(req).await;
            return Arc::new(result);
        }
        let cell = self
            .cache
            .entry(req.clone())
            .or_insert_with(|| Arc::new(OnceCell::new()))
            .value()
            .clone();

        let result = cell
            .get_or_init(|| async {
                let value = self.handler.handle(req.clone()).await;
                self.cache.remove(&req);
                return Arc::new(value);
            })
            .await;

        result.clone()
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
/// LoggingFilter::new(RequestFilter)
#[macro_export]
macro_rules! compose_filters {
    ($last:expr) => {
        $last
    };
    ($head:ident, $($tail:tt)*) => {
        $head::new(compose_filters!($($tail)*))
    };
}

type DefaultFilters = SingleGetFilter<LoggingFilter<RequestFilter>>;
pub static DEFAULT_FILTERS: LazyLock<DefaultFilters> =
    LazyLock::new(|| compose_filters!(SingleGetFilter, LoggingFilter, RequestFilter));
