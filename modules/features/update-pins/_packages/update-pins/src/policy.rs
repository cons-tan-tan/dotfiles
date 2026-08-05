use std::time::Duration;

pub const DEFAULT_MAX_ATTEMPTS: u8 = 3;
pub const MAX_ATTEMPTS_LIMIT: u8 = 5;
// Keep parallelism opt-in: the current-pin benchmark improved the overall
// median by only 4.6%, despite a material improvement for hcom.
pub const DEFAULT_ASSET_JOBS: u8 = 1;
pub const MAX_ASSET_JOBS_LIMIT: u8 = 4;

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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AssetJobsPolicy {
    max_jobs: u8,
}

impl Default for AssetJobsPolicy {
    fn default() -> Self {
        Self {
            max_jobs: DEFAULT_ASSET_JOBS,
        }
    }
}

impl AssetJobsPolicy {
    pub fn new(max_jobs: u8) -> Option<Self> {
        (1..=MAX_ASSET_JOBS_LIMIT)
            .contains(&max_jobs)
            .then_some(Self { max_jobs })
    }

    pub fn max_jobs(self) -> usize {
        usize::from(self.max_jobs)
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RunPolicy {
    pub force: bool,
    pub retry: RetryPolicy,
    pub asset_jobs: AssetJobsPolicy,
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{AssetJobsPolicy, RetryPolicy, RunPolicy};

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

    #[test]
    fn asset_jobs_policy_defaults_to_one_and_accepts_one_through_four() {
        assert_eq!(AssetJobsPolicy::default().max_jobs(), 1);
        assert_eq!(RunPolicy::default().asset_jobs.max_jobs(), 1);
        for jobs in 1..=4 {
            assert_eq!(
                AssetJobsPolicy::new(jobs).map(AssetJobsPolicy::max_jobs),
                Some(usize::from(jobs))
            );
        }
    }

    #[test]
    fn asset_jobs_policy_rejects_out_of_bounds_counts() {
        assert_eq!(AssetJobsPolicy::new(0), None);
        assert_eq!(AssetJobsPolicy::new(5), None);
    }
}
