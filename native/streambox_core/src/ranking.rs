use std::collections::HashSet;

use regex_lite::Regex;
use std::sync::LazyLock;

// ── Tokenization ──────────────────────────────────────────────────────────────

/// Split text into lowercase alphanumeric tokens of length > 1.
/// This is the canonical shared tokenizer; both db and musicbrainz modules
/// wrap it in their own `HashSet`-returning helpers.
pub fn tokenize(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|s| s.len() > 1)
        .map(String::from)
        .collect()
}

/// Filter `tokens` to only those not appearing in `stop_words`.
pub fn core_tokens(tokens: &[String], stop_words: &[&str]) -> Vec<String> {
    let stop_set: HashSet<&str> = stop_words.iter().copied().collect();
    tokens
        .iter()
        .filter(|t| !stop_set.contains(t.as_str()))
        .cloned()
        .collect()
}

// ── Token overlap ────────────────────────────────────────────────────────────

/// Statistics describing the overlap between two token lists (as sets).
pub struct TokenOverlap {
    /// Size of the intersection of the two token sets.
    pub intersection: usize,
    /// Size of the union of the two token sets.
    pub union: usize,
    /// Intersection / union ratio.
    pub ratio: f64,
}

/// Compute overlap statistics between two token lists (treated as sets).
pub fn compute_overlap(query_tokens: &[String], result_tokens: &[String]) -> TokenOverlap {
    let q_set: HashSet<&str> = query_tokens.iter().map(|s| s.as_str()).collect();
    let r_set: HashSet<&str> = result_tokens.iter().map(|s| s.as_str()).collect();
    let intersection = q_set.intersection(&r_set).count();
    let union = q_set.union(&r_set).count();
    let ratio = if union > 0 {
        intersection as f64 / union as f64
    } else {
        0.0
    };
    TokenOverlap {
        intersection,
        union,
        ratio,
    }
}

// ── Title normalization helpers ───────────────────────────────────────────────

static PAREN_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\([^)]*\)").unwrap());

/// Remove parenthetical content from a title (e.g., `"Song (Live)"` → `"Song"`).
pub fn strip_parenthetical(title: &str) -> String {
    PAREN_RE.replace_all(title, "").trim().to_string()
}

/// Normalize a title: strip parentheticals, tokenize, remove stop words, sort,
/// and join back into a string.  Useful for exact-match comparisons.
pub fn normalize_title(title: &str, stop_words: &[&str]) -> String {
    let stripped = strip_parenthetical(title);
    let tokens = tokenize(&stripped);
    let mut core = core_tokens(&tokens, stop_words);
    core.sort();
    core.join(" ")
}

// ── Cue-word penalty ─────────────────────────────────────────────────────────

/// Calculate a base penalty for unexpected cue words (e.g., "live", "cover",
/// "remix") appearing in a title but NOT in the query.  Returns a negative
/// score that modules can add (or ignore) at their own weights.
///
/// The caller should pass the set of cue words that match **their**
/// domain-specific list.
pub fn cue_penalty(title: &str, cue_words: &[&str]) -> i32 {
    let title_tokens: HashSet<String> = tokenize(title).into_iter().collect();
    let cue_set: HashSet<&str> = cue_words.iter().copied().collect();
    let unexpected: Vec<_> = title_tokens
        .iter()
        .filter(|t| cue_set.contains(t.as_str()))
        .collect();
    if unexpected.is_empty() {
        0
    } else {
        -(55 + unexpected.len() as i32 * 12)
    }
}

// ── Duration scoring ─────────────────────────────────────────────────────────

/// Return a base score contribution for a track duration.
///
/// * `duration_secs` – the duration (may be `None`).
/// * `min` / `max`  – the ideal range (e.g. 120.0 … 420.0).
///
/// Returns `12` when the duration falls inside `[min, max]`,
/// `-35` when it is extreme (<45 s or >900 s), and `0` otherwise.
/// Callers may adjust the returned value with their own weights.
pub fn duration_score(duration_secs: Option<f64>, min: f64, max: f64) -> i32 {
    match duration_secs {
        Some(d) if d >= min && d <= max => 12,
        Some(d) if !(45.0..=900.0).contains(&d) => -35,
        _ => 0,
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tokenize_basic() {
        let result = tokenize("Hello World");
        assert_eq!(result.len(), 2);
        assert!(result.contains(&"hello".to_string()));
        assert!(result.contains(&"world".to_string()));
    }

    #[test]
    fn test_tokenize_short_skipped() {
        let result = tokenize("a b c d");
        assert!(result.is_empty());
    }

    #[test]
    fn test_tokenize_mixed() {
        let result = tokenize("The Beat of a Drum");
        assert!(!result.contains(&"a".to_string()));
        assert!(result.contains(&"of".to_string()));
        assert!(result.contains(&"the".to_string()));
        assert!(result.contains(&"beat".to_string()));
        assert!(result.contains(&"drum".to_string()));
    }

    #[test]
    fn test_tokenize_punctuation() {
        let result = tokenize("Hello-World! It's great");
        assert!(result.contains(&"hello".to_string()));
        assert!(result.contains(&"world".to_string()));
        assert!(result.contains(&"great".to_string()));
    }

    #[test]
    fn test_core_tokens_removes_stop_words() {
        let stop_words = &["the", "of", "a"];
        let tokens = tokenize("The Beat of a Drum");
        let result = core_tokens(&tokens, stop_words);
        assert!(!result.contains(&"the".to_string()));
        assert!(!result.contains(&"of".to_string()));
        assert!(!result.contains(&"a".to_string()));
        assert!(result.contains(&"beat".to_string()));
        assert!(result.contains(&"drum".to_string()));
    }

    #[test]
    fn test_core_tokens_no_stop_words() {
        let stop_words: &[&str] = &[];
        let tokens = tokenize("hello world");
        let result = core_tokens(&tokens, stop_words);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn test_strip_parenthetical() {
        assert_eq!(strip_parenthetical("Hello (Live)"), "Hello");
        assert_eq!(
            strip_parenthetical("Hello (Live At Wembley) World"),
            "Hello  World"
        );
        assert_eq!(strip_parenthetical("No Parens"), "No Parens");
        assert_eq!(strip_parenthetical("(Intro)"), "");
        assert_eq!(strip_parenthetical(""), "");
    }

    #[test]
    fn test_normalize_title() {
        let stop_words = &[
            "a",
            "an",
            "and",
            "feat",
            "featuring",
            "in",
            "of",
            "the",
            "to",
        ];
        let result = normalize_title("Bohemian Rhapsody (Live)", stop_words);
        assert_eq!(result, "bohemian rhapsody");
    }

    #[test]
    fn test_normalize_title_no_strip() {
        let stop_words = &["the"];
        let result = normalize_title("The Scientist", stop_words);
        assert_eq!(result, "scientist");
    }

    #[test]
    fn test_compute_overlap() {
        let q = tokenize("hello world");
        let r = tokenize("hello there");
        let overlap = compute_overlap(&q, &r);
        assert_eq!(overlap.intersection, 1);
        assert_eq!(overlap.union, 3);
        assert!((overlap.ratio - 1.0 / 3.0).abs() < 0.001);
    }

    #[test]
    fn test_compute_overlap_empty_query() {
        let q: Vec<String> = vec![];
        let r = tokenize("hello world");
        let overlap = compute_overlap(&q, &r);
        assert_eq!(overlap.intersection, 0);
        assert_eq!(overlap.ratio, 0.0);
    }

    #[test]
    fn test_compute_overlap_identical() {
        let q = tokenize("hello world");
        let r = tokenize("hello world");
        let overlap = compute_overlap(&q, &r);
        assert_eq!(overlap.intersection, 2);
        assert_eq!(overlap.union, 2);
        assert!((overlap.ratio - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_cue_penalty_no_cues() {
        let result = cue_penalty("Hello World", &["live", "cover", "remix"]);
        assert_eq!(result, 0);
    }

    #[test]
    fn test_cue_penalty_with_cues() {
        let result = cue_penalty("Song (Live)", &["live", "cover", "remix"]);
        assert!(result < 0);
    }

    #[test]
    fn test_cue_penalty_empty_cue_list() {
        let result = cue_penalty("Song (Live)", &[]);
        assert_eq!(result, 0);
    }

    #[test]
    fn test_duration_score_ideal() {
        assert_eq!(duration_score(Some(180.0), 120.0, 420.0), 12);
        assert_eq!(duration_score(Some(120.0), 120.0, 420.0), 12);
        assert_eq!(duration_score(Some(420.0), 120.0, 420.0), 12);
    }

    #[test]
    fn test_duration_score_extreme() {
        assert_eq!(duration_score(Some(30.0), 120.0, 420.0), -35);
        assert_eq!(duration_score(Some(1000.0), 120.0, 420.0), -35);
    }

    #[test]
    fn test_duration_score_neutral() {
        assert_eq!(duration_score(Some(60.0), 120.0, 420.0), 0);
        assert_eq!(duration_score(Some(500.0), 120.0, 420.0), 0);
    }

    #[test]
    fn test_duration_score_none() {
        assert_eq!(duration_score(None, 120.0, 420.0), 0);
    }
}
