use std::process::ExitCode;
use std::time::Duration;

async fn collection_is_unlocked() -> Result<bool, oo7::dbus::Error> {
    let service = oo7::dbus::Service::plain().await?;
    let Some(collection) = service
        .with_alias(oo7::dbus::Service::DEFAULT_COLLECTION)
        .await?
    else {
        return Ok(false);
    };
    Ok(!collection.is_locked().await?)
}

#[tokio::main]
async fn main() -> ExitCode {
    const ATTEMPTS: usize = 50;
    const RETRY_DELAY: Duration = Duration::from_millis(100);

    let mut last_error = None;
    for attempt in 0..ATTEMPTS {
        match collection_is_unlocked().await {
            Ok(true) => return ExitCode::SUCCESS,
            Ok(false) => last_error = Some("default collection is missing or locked".to_owned()),
            Err(error) => last_error = Some(error.to_string()),
        }
        if attempt + 1 < ATTEMPTS {
            tokio::time::sleep(RETRY_DELAY).await;
        }
    }

    eprintln!(
        "oo7-unlock-check: {}",
        last_error.unwrap_or_else(|| "unlock status could not be determined".to_owned())
    );
    ExitCode::FAILURE
}
