use std::time::Duration;

pub const DEFAULT_MAX_ATTEMPTS: u8 = 3;
pub const MAX_ATTEMPTS_LIMIT: u8 = 5;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RetryPolicy {
    max_attempts: u8,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_attempts: DEFAULT_MAX_ATTEMPTS,
        }
    }
}

impl RetryPolicy {
    pub fn new(max_attempts: u8) -> Option<Self> {
        (1..=MAX_ATTEMPTS_LIMIT)
            .contains(&max_attempts)
            .then_some(Self { max_attempts })
    }

    pub fn max_attempts(self) -> u8 {
        self.max_attempts
    }

    pub fn backoff_after(self, completed_attempt: u8) -> Duration {
        let exponent = u32::from(completed_attempt.saturating_sub(1).min(3));
        Duration::from_millis(250 * 2_u64.pow(exponent))
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RunPolicy {
    pub force: bool,
    pub retry: RetryPolicy,
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::RetryPolicy;

    #[test]
    fn retry_backoff_is_bounded_exponential() {
        let policy = RetryPolicy::new(5).expect("valid retry policy");
        assert_eq!(
            (1..=4)
                .map(|attempt| policy.backoff_after(attempt))
                .collect::<Vec<_>>(),
            [
                Duration::from_millis(250),
                Duration::from_millis(500),
                Duration::from_millis(1_000),
                Duration::from_millis(2_000),
            ]
        );
    }

    #[test]
    fn retry_policy_rejects_out_of_bounds_attempt_counts() {
        assert_eq!(RetryPolicy::new(0), None);
        assert_eq!(RetryPolicy::new(1).map(RetryPolicy::max_attempts), Some(1));
        assert_eq!(RetryPolicy::new(5).map(RetryPolicy::max_attempts), Some(5));
        assert_eq!(RetryPolicy::new(6), None);
    }
}
