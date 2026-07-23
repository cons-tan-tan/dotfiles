use std::collections::HashSet;
use std::fs::File;
use std::io::{Cursor, Read as _};
use std::path::Path;

use plist::stream::{Event as PlistEvent, Reader as PlistReader};
use quick_xml::XmlVersion;
use quick_xml::escape::unescape;
use quick_xml::events::{BytesStart, Event};
use quick_xml::name::ResolveResult;
use quick_xml::reader::NsReader;
use rawzip::{CompressionMethod, RECOMMENDED_BUFFER_SIZE, ZipArchive, ZipArchiveEntryWayfinder};

use crate::command::{CommandRunner, CommandSpec, run_checked_limited};
use crate::error::UpdateError;
use crate::pins::PinDocument;
use crate::prefetch::prefetch_result;
use crate::registry::TargetSpec;
use crate::targets::validate_release_version;
use crate::transaction::Transaction;

const MAX_APPCAST_BYTES: usize = 4 * 1024 * 1024;
const MAX_APPCAST_DEPTH: usize = 128;
const MAX_APPCAST_STDERR_BYTES: usize = 64 * 1024;
const MAX_PLIST_BYTES: u64 = 4 * 1024 * 1024;
const MAX_PLIST_DEPTH: usize = 128;
const MAX_PLIST_EVENTS: usize = 16_384;
const MAX_PLIST_SCALAR_BYTES: usize = 4 * 1024 * 1024;
const MAX_ZIP_BYTES: u64 = 1024 * 1024 * 1024;
const MAX_ZIP_ENTRIES: u64 = 100_000;
const MAX_ZIP_PATH_BYTES: usize = 4_096;
const MAX_TOTAL_ZIP_PATH_BYTES: usize = 16 * 1024 * 1024;
const APPCAST_URL: &str = "https://persistent.oaistatic.com/codex-app-prod/appcast.xml";
const SPARKLE_NAMESPACE: &[u8] = b"http://www.andymatuschak.org/xml-namespaces/sparkle";

#[derive(Debug, Eq, PartialEq)]
struct AppcastCandidate {
    version: String,
    url: String,
}

#[derive(Default)]
struct AppcastItem {
    title: String,
    short_version: String,
    hardware: String,
    enclosure_urls: Vec<String>,
}

#[derive(Clone, Copy)]
enum TextField {
    Title,
    ShortVersion,
    Hardware,
}

#[derive(Debug)]
struct BundleIdentity {
    app_name: String,
    bundle_identifier: String,
    display_name: String,
    version: String,
}

struct BundleCandidate {
    wayfinder: ZipArchiveEntryWayfinder,
    compression: CompressionMethod,
    path: Vec<u8>,
    app_name: String,
}

#[derive(Clone, Copy)]
enum BundleField {
    Identifier,
    DisplayName,
    Name,
    Version,
}

enum ParsedField {
    Missing,
    String(String),
    Invalid,
}

struct ParsedBundleFields {
    identifier: ParsedField,
    display_name: ParsedField,
    name: ParsedField,
    version: ParsedField,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum NamespaceKind {
    Unbound,
    Sparkle,
    Other,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum ElementKind {
    Channel,
    Item,
    Title,
    ShortVersion,
    Hardware,
    Enclosure,
    Other,
}

pub fn update<R: CommandRunner>(
    spec: &TargetSpec,
    pin_path: &str,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let mut pin = PinDocument::parse(pin_path, transaction.read(pin_path)?)?;
    let appcast_url = pin.string(&["appcast"])?.to_owned();
    let current_version = pin.string(&["version"])?.to_owned();
    let current_url = pin.string(&["url"])?.to_owned();
    let expected_app_name = pin.string(&["appName"])?.to_owned();
    let expected_bundle_identifier = pin.string(&["bundleIdentifier"])?.to_owned();
    let expected_display_name = pin.string(&["displayName"])?.to_owned();
    if appcast_url != APPCAST_URL {
        return Err(UpdateError::message(format!(
            "{pin_path}: unsupported appcast URL {appcast_url:?}"
        )));
    }

    let command = CommandSpec::new("curl")
        .args(["-fsSL", &appcast_url])
        .current_dir(transaction.root());
    let output = run_checked_limited(
        runner,
        &command,
        MAX_APPCAST_BYTES,
        MAX_APPCAST_STDERR_BYTES,
    )?;
    let latest = parse_appcast(&output.stdout, pin_path)?;
    if latest.version == current_version && latest.url == current_url {
        println!("{}: {current_version} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: {current_version} -> {} (prefetching app...)",
        spec.name, latest.version
    );
    let prefetched = prefetch_result(
        &format!("{}: {pin_path}: hash", spec.name),
        runner,
        transaction.root(),
        &latest.url,
        false,
    )?;
    let store_path = prefetched.store_path.ok_or_else(|| {
        UpdateError::message(format!(
            "{pin_path}: prefetch did not return storePath for {}",
            latest.url
        ))
    })?;
    require_regular_store_file(&store_path, pin_path)?;
    let bundle = inspect_bundle(&store_path, pin_path)?;

    if bundle.version != latest.version {
        return Err(UpdateError::message(format!(
            "{}: {pin_path}: version: appcast version {} did not match bundle version {}",
            spec.name, latest.version, bundle.version,
        )));
    }
    if bundle.app_name != expected_app_name {
        return Err(UpdateError::message(format!(
            "{}: {pin_path}: appName: expected app name {expected_app_name} but downloaded {}",
            spec.name, bundle.app_name
        )));
    }
    if bundle.bundle_identifier != expected_bundle_identifier {
        return Err(UpdateError::message(format!(
            "{}: {pin_path}: bundleIdentifier: expected bundle identifier \
             {expected_bundle_identifier} but downloaded {}",
            spec.name, bundle.bundle_identifier
        )));
    }
    if bundle.display_name != expected_display_name {
        return Err(UpdateError::message(format!(
            "{}: {pin_path}: displayName: expected display name \
             {expected_display_name} but downloaded {}",
            spec.name, bundle.display_name
        )));
    }

    pin.set_string(&["version"], &latest.version)?;
    pin.set_string(&["url"], &latest.url)?;
    pin.set_string(&["hash"], prefetched.hash)?;
    if let Some(rendered) = pin.rendered()? {
        transaction.replace(pin_path, &rendered)?;
    }
    Ok(true)
}

fn parse_appcast(bytes: &[u8], pin_path: &str) -> Result<AppcastCandidate, UpdateError> {
    if bytes.len() > MAX_APPCAST_BYTES {
        return Err(UpdateError::message(format!(
            "{pin_path}: appcast exceeded {MAX_APPCAST_BYTES} bytes"
        )));
    }
    let mut reader = NsReader::from_reader(bytes);
    reader.config_mut().trim_text(true);
    let mut stack: Vec<ElementKind> = Vec::new();
    let mut item: Option<(usize, AppcastItem)> = None;
    let mut text_field: Option<TextField> = None;
    let mut selected = None;
    let mut root_count = 0_u8;

    loop {
        let (namespace, event) = reader.read_resolved_event().map_err(|source| {
            UpdateError::message(format!("{pin_path}: malformed appcast XML: {source}"))
        })?;
        let namespace = namespace_kind(namespace, pin_path)?;
        match event {
            Event::Start(element) => {
                if stack.len() >= MAX_APPCAST_DEPTH {
                    return Err(UpdateError::message(format!(
                        "{pin_path}: appcast exceeded XML depth {MAX_APPCAST_DEPTH}"
                    )));
                }
                if stack.is_empty() {
                    root_count = root_count.saturating_add(1);
                    if root_count > 1 {
                        return Err(UpdateError::message(format!(
                            "{pin_path}: appcast contained multiple root elements"
                        )));
                    }
                }
                let kind = element_kind(namespace, element.local_name().as_ref());
                if kind == ElementKind::Item
                    && stack.len() == 2
                    && stack.last() == Some(&ElementKind::Channel)
                    && item.is_none()
                    && selected.is_none()
                {
                    item = Some((stack.len() + 1, AppcastItem::default()));
                } else if let Some((item_depth, current)) = item.as_mut()
                    && stack.len() == *item_depth
                {
                    match kind {
                        ElementKind::Title => text_field = Some(TextField::Title),
                        ElementKind::ShortVersion => {
                            text_field = Some(TextField::ShortVersion);
                        }
                        ElementKind::Hardware => {
                            text_field = Some(TextField::Hardware);
                        }
                        ElementKind::Enclosure => {
                            if let Some(url) = read_url_attribute(&element, pin_path)? {
                                current.enclosure_urls.push(url);
                            }
                        }
                        _ => {}
                    }
                }
                stack.push(kind);
            }
            Event::Empty(element) => {
                if stack.is_empty() {
                    root_count = root_count.saturating_add(1);
                    if root_count > 1 {
                        return Err(UpdateError::message(format!(
                            "{pin_path}: appcast contained multiple root elements"
                        )));
                    }
                }
                let kind = element_kind(namespace, element.local_name().as_ref());
                if let Some((item_depth, current)) = item.as_mut()
                    && stack.len() == *item_depth
                    && kind == ElementKind::Enclosure
                    && let Some(url) = read_url_attribute(&element, pin_path)?
                {
                    current.enclosure_urls.push(url);
                }
            }
            Event::Text(text) => {
                if let (Some(field), Some((_, current))) = (text_field, item.as_mut()) {
                    let decoded = text.decode().map_err(|source| {
                        UpdateError::message(format!(
                            "{pin_path}: invalid appcast text encoding: {source}"
                        ))
                    })?;
                    let value = unescape(&decoded).map_err(|source| {
                        UpdateError::message(format!(
                            "{pin_path}: invalid appcast text escape: {source}"
                        ))
                    })?;
                    append_text(current, field, &value);
                }
            }
            Event::CData(text) => {
                if let (Some(field), Some((_, current))) = (text_field, item.as_mut()) {
                    let value = text.decode().map_err(|source| {
                        UpdateError::message(format!(
                            "{pin_path}: invalid appcast CDATA encoding: {source}"
                        ))
                    })?;
                    append_text(current, field, &value);
                }
            }
            Event::End(element) => {
                let kind = element_kind(namespace, element.local_name().as_ref());
                if matches!(
                    kind,
                    ElementKind::Title | ElementKind::ShortVersion | ElementKind::Hardware
                ) {
                    text_field = None;
                }
                if kind == ElementKind::Item
                    && item
                        .as_ref()
                        .is_some_and(|(item_depth, _)| stack.len() == *item_depth)
                {
                    let (_, completed) = item.take().expect("checked item presence");
                    if selected.is_none() {
                        selected = candidate_from_item(completed, pin_path)?;
                    }
                }
                stack.pop();
            }
            Event::DocType(_) => {
                return Err(UpdateError::message(format!(
                    "{pin_path}: appcast document types are not supported"
                )));
            }
            Event::Eof => break,
            _ => {}
        }
    }

    if root_count != 1 || !stack.is_empty() {
        return Err(UpdateError::message(format!(
            "{pin_path}: malformed appcast XML document"
        )));
    }
    selected.ok_or_else(|| {
        UpdateError::message(format!(
            "{pin_path}: appcast did not contain a darwin arm64 enclosure"
        ))
    })
}

fn read_url_attribute(
    element: &BytesStart<'_>,
    pin_path: &str,
) -> Result<Option<String>, UpdateError> {
    let mut urls = Vec::new();
    for attribute in element.attributes() {
        let attribute = attribute.map_err(|source| {
            UpdateError::message(format!("{pin_path}: invalid appcast attribute: {source}"))
        })?;
        if attribute.key.as_ref() == b"url" {
            let value = attribute
                .decoded_and_normalized_value(XmlVersion::Implicit1_0, element.decoder())
                .map_err(|source| {
                    UpdateError::message(format!(
                        "{pin_path}: invalid appcast enclosure URL: {source}"
                    ))
                })?;
            urls.push(value.into_owned());
        }
    }
    match urls.as_slice() {
        [url] => Ok(Some(url.clone())),
        [] => Ok(None),
        _ => Err(UpdateError::message(format!(
            "{pin_path}: appcast enclosure has multiple url attributes"
        ))),
    }
}

fn namespace_kind(
    namespace: ResolveResult<'_>,
    pin_path: &str,
) -> Result<NamespaceKind, UpdateError> {
    match namespace {
        ResolveResult::Unbound => Ok(NamespaceKind::Unbound),
        ResolveResult::Bound(namespace) if namespace.as_ref() == SPARKLE_NAMESPACE => {
            Ok(NamespaceKind::Sparkle)
        }
        ResolveResult::Bound(_) => Ok(NamespaceKind::Other),
        ResolveResult::Unknown(prefix) => Err(UpdateError::message(format!(
            "{pin_path}: appcast used unknown namespace prefix {}",
            String::from_utf8_lossy(&prefix)
        ))),
    }
}

fn element_kind(namespace: NamespaceKind, local: &[u8]) -> ElementKind {
    match (namespace, local) {
        (NamespaceKind::Unbound, b"channel") => ElementKind::Channel,
        (NamespaceKind::Unbound, b"item") => ElementKind::Item,
        (NamespaceKind::Unbound, b"title") => ElementKind::Title,
        (NamespaceKind::Sparkle, b"shortVersionString") => ElementKind::ShortVersion,
        (NamespaceKind::Sparkle, b"hardwareRequirements") => ElementKind::Hardware,
        (NamespaceKind::Unbound, b"enclosure") => ElementKind::Enclosure,
        _ => ElementKind::Other,
    }
}

fn append_text(item: &mut AppcastItem, field: TextField, value: &str) {
    match field {
        TextField::Title => item.title.push_str(value),
        TextField::ShortVersion => item.short_version.push_str(value),
        TextField::Hardware => item.hardware.push_str(value),
    }
}

fn candidate_from_item(
    item: AppcastItem,
    pin_path: &str,
) -> Result<Option<AppcastCandidate>, UpdateError> {
    if !item.hardware.is_empty() && item.hardware.trim() != "arm64" {
        return Ok(None);
    }
    let version = if item.short_version.is_empty() {
        item.title
    } else {
        item.short_version
    };
    if version.is_empty() {
        return Ok(None);
    }
    let urls: Vec<_> = item
        .enclosure_urls
        .into_iter()
        .filter(|url| url.contains("darwin-arm64"))
        .collect();
    match urls.as_slice() {
        [url] => {
            validate_release_version("codex-app", &version)?;
            validate_app_download_url(url, &version, pin_path)?;
            Ok(Some(AppcastCandidate {
                version,
                url: url.clone(),
            }))
        }
        [] => Ok(None),
        _ => Err(UpdateError::message(format!(
            "{pin_path}: appcast item {version} contained multiple darwin arm64 enclosures"
        ))),
    }
}

fn validate_app_download_url(url: &str, version: &str, pin_path: &str) -> Result<(), UpdateError> {
    let expected = format!(
        "https://persistent.oaistatic.com/codex-app-prod/\
         ChatGPT-darwin-arm64-{version}.zip"
    );
    if url == expected {
        Ok(())
    } else {
        Err(UpdateError::message(format!(
            "{pin_path}: appcast contained an unsupported app download URL"
        )))
    }
}

fn require_regular_store_file(path: &Path, pin_path: &str) -> Result<(), UpdateError> {
    if !path.is_absolute() {
        return Err(UpdateError::message(format!(
            "{pin_path}: prefetch returned non-absolute storePath {}",
            path.display()
        )));
    }
    let metadata =
        std::fs::symlink_metadata(path).map_err(|source| UpdateError::io(path, source))?;
    if metadata.is_file() && !metadata.file_type().is_symlink() {
        Ok(())
    } else {
        Err(UpdateError::message(format!(
            "{pin_path}: prefetch storePath is not a regular file: {}",
            path.display()
        )))
    }
}

fn inspect_bundle(path: &Path, pin_path: &str) -> Result<BundleIdentity, UpdateError> {
    let file = File::open(path).map_err(|source| UpdateError::io(path, source))?;
    let archive_size = file
        .metadata()
        .map_err(|source| UpdateError::io(path, source))?
        .len();
    if archive_size > MAX_ZIP_BYTES {
        return Err(UpdateError::message(format!(
            "{pin_path}: app ZIP exceeded {MAX_ZIP_BYTES} bytes"
        )));
    }

    let mut archive_buffer = vec![0; RECOMMENDED_BUFFER_SIZE];
    let archive = ZipArchive::from_file(file, &mut archive_buffer)
        .map_err(|source| UpdateError::message(format!("{pin_path}: invalid app ZIP: {source}")))?;
    let expected_entries = archive.entries_hint();
    if expected_entries > MAX_ZIP_ENTRIES {
        return Err(UpdateError::message(format!(
            "{pin_path}: app ZIP exceeded {MAX_ZIP_ENTRIES} entries"
        )));
    }

    let mut actual_entries = 0_u64;
    let mut total_path_bytes = 0_usize;
    let mut seen_paths = HashSet::new();
    let mut candidates = Vec::new();
    let mut entries = archive.entries(&mut archive_buffer);
    while let Some(entry) = entries.next_entry().map_err(|source| {
        UpdateError::message(format!(
            "{pin_path}: failed to inspect app ZIP central directory: {source}"
        ))
    })? {
        actual_entries += 1;
        if actual_entries > MAX_ZIP_ENTRIES {
            return Err(UpdateError::message(format!(
                "{pin_path}: app ZIP exceeded {MAX_ZIP_ENTRIES} entries"
            )));
        }

        let name = entry.file_path().as_bytes();
        validate_zip_path(name, pin_path)?;
        total_path_bytes = total_path_bytes
            .checked_add(name.len())
            .filter(|total| *total <= MAX_TOTAL_ZIP_PATH_BYTES)
            .ok_or_else(|| {
                UpdateError::message(format!(
                    "{pin_path}: app ZIP paths exceeded {MAX_TOTAL_ZIP_PATH_BYTES} total bytes"
                ))
            })?;
        if !seen_paths.insert(name.to_vec()) {
            return Err(UpdateError::message(format!(
                "{pin_path}: app ZIP contained duplicate entry path {:?}",
                String::from_utf8_lossy(name)
            )));
        }
        let components: Vec<_> = name.split(|byte| *byte == b'/').collect();
        if components.len() == 3
            && components[0].len() > ".app".len()
            && components[0].ends_with(b".app")
            && components[1] == b"Contents"
            && components[2] == b"Info.plist"
        {
            if entry.flags().is_encrypted()
                || entry.is_dir()
                || entry.mode().is_symlink()
                || entry.mode().value() & 0o170_000 != 0o100_000
            {
                return Err(UpdateError::message(format!(
                    "{pin_path}: app ZIP Info.plist is not a regular file"
                )));
            }
            if entry.uncompressed_size_hint() > MAX_PLIST_BYTES {
                return Err(UpdateError::message(format!(
                    "{pin_path}: app ZIP Info.plist exceeded {MAX_PLIST_BYTES} bytes"
                )));
            }
            let compression = entry.compression_method();
            if !matches!(
                compression,
                CompressionMethod::STORE | CompressionMethod::DEFLATE
            ) {
                return Err(UpdateError::message(format!(
                    "{pin_path}: app ZIP Info.plist used unsupported compression {compression}"
                )));
            }
            let app_name = std::str::from_utf8(components[0]).map_err(|source| {
                UpdateError::message(format!(
                    "{pin_path}: app ZIP bundle name is not valid UTF-8: {source}"
                ))
            })?;
            candidates.push(BundleCandidate {
                wayfinder: entry.wayfinder(),
                compression,
                path: name.to_vec(),
                app_name: app_name.to_owned(),
            });
        }
    }
    if actual_entries != expected_entries {
        return Err(UpdateError::message(format!(
            "{pin_path}: app ZIP entry count mismatch: expected {expected_entries}, \
             inspected {actual_entries}"
        )));
    }
    let candidate = match candidates.as_slice() {
        [candidate] => candidate,
        [] => {
            return Err(UpdateError::message(format!(
                "{pin_path}: app ZIP did not contain a top-level .app/Contents/Info.plist"
            )));
        }
        _ => {
            return Err(UpdateError::message(format!(
                "{pin_path}: app ZIP contained multiple top-level .app/Contents/Info.plist entries"
            )));
        }
    };

    let entry = archive.get_entry(candidate.wayfinder).map_err(|source| {
        UpdateError::message(format!(
            "{pin_path}: failed to open app ZIP Info.plist: {source}"
        ))
    })?;
    let mut local_header_buffer = vec![0; usize::from(u16::MAX) * 2];
    let local_header = entry
        .local_header(&mut local_header_buffer)
        .map_err(|source| {
            UpdateError::message(format!(
                "{pin_path}: invalid app ZIP Info.plist local header: {source}"
            ))
        })?;
    if local_header.file_path().as_bytes() != candidate.path
        || local_header.flags().is_encrypted()
        || local_header.compression_method() != candidate.compression
    {
        return Err(UpdateError::message(format!(
            "{pin_path}: app ZIP Info.plist local header did not match its central directory entry"
        )));
    }

    let mut bytes = Vec::new();
    let read_result = match candidate.compression {
        CompressionMethod::STORE => entry
            .verifying_reader(entry.reader())
            .take(MAX_PLIST_BYTES + 1)
            .read_to_end(&mut bytes),
        CompressionMethod::DEFLATE => entry
            .verifying_reader(flate2::read::DeflateDecoder::new(entry.reader()))
            .take(MAX_PLIST_BYTES + 1)
            .read_to_end(&mut bytes),
        _ => unreachable!("candidate compression was validated"),
    };
    read_result.map_err(|source| {
        UpdateError::message(format!(
            "{pin_path}: failed to read or verify app ZIP Info.plist: {source}"
        ))
    })?;
    if bytes.len() as u64 > MAX_PLIST_BYTES {
        return Err(UpdateError::message(format!(
            "{pin_path}: app ZIP Info.plist exceeded {MAX_PLIST_BYTES} bytes"
        )));
    }
    parse_bundle_identity(&bytes, candidate.app_name.clone(), pin_path)
}

fn parse_bundle_identity(
    bytes: &[u8],
    app_name: String,
    pin_path: &str,
) -> Result<BundleIdentity, UpdateError> {
    let mut reader = PlistReader::new(Cursor::new(bytes));
    let mut event_count = 0_usize;
    let mut scalar_bytes = 0_usize;
    let first = next_plist_event(&mut reader, &mut event_count, &mut scalar_bytes, pin_path)?
        .ok_or_else(|| UpdateError::message(format!("{pin_path}: Info.plist was empty")))?;
    if !matches!(first, PlistEvent::StartDictionary(_)) {
        return Err(UpdateError::message(format!(
            "{pin_path}: Info.plist root is not a dictionary"
        )));
    }

    let mut fields = ParsedBundleFields::default();
    let mut expecting_key = true;
    let mut pending_field = None;
    let mut depth = 1_usize;
    let mut skipped_value_depth = None;
    loop {
        let event = next_plist_event(&mut reader, &mut event_count, &mut scalar_bytes, pin_path)?
            .ok_or_else(|| {
            UpdateError::message(format!("{pin_path}: truncated Info.plist dictionary"))
        })?;

        if let Some(start_depth) = skipped_value_depth {
            match event {
                PlistEvent::StartArray(_) | PlistEvent::StartDictionary(_) => {
                    depth = depth.checked_add(1).ok_or_else(|| {
                        UpdateError::message(format!("{pin_path}: Info.plist depth overflow"))
                    })?;
                    require_plist_depth(depth, pin_path)?;
                }
                PlistEvent::EndCollection => {
                    depth = depth.checked_sub(1).ok_or_else(|| {
                        UpdateError::message(format!(
                            "{pin_path}: invalid Info.plist collection end"
                        ))
                    })?;
                    if depth < start_depth {
                        skipped_value_depth = None;
                        expecting_key = true;
                    }
                }
                _ => {}
            }
            continue;
        }

        if expecting_key {
            match event {
                PlistEvent::EndCollection => {
                    depth = depth.checked_sub(1).ok_or_else(|| {
                        UpdateError::message(format!(
                            "{pin_path}: invalid Info.plist collection end"
                        ))
                    })?;
                    break;
                }
                PlistEvent::String(key) => {
                    pending_field = bundle_field(&key);
                    expecting_key = false;
                }
                _ => {
                    return Err(UpdateError::message(format!(
                        "{pin_path}: Info.plist dictionary key is not a string"
                    )));
                }
            }
        } else {
            match event {
                PlistEvent::String(value) => {
                    if let Some(field) = pending_field.take() {
                        fields.record(field, ParsedField::String(value.into_owned()), pin_path)?;
                    }
                    expecting_key = true;
                }
                PlistEvent::StartArray(_) | PlistEvent::StartDictionary(_) => {
                    if let Some(field) = pending_field.take() {
                        fields.record(field, ParsedField::Invalid, pin_path)?;
                    }
                    depth = depth.checked_add(1).ok_or_else(|| {
                        UpdateError::message(format!("{pin_path}: Info.plist depth overflow"))
                    })?;
                    require_plist_depth(depth, pin_path)?;
                    skipped_value_depth = Some(depth);
                }
                PlistEvent::EndCollection => {
                    return Err(UpdateError::message(format!(
                        "{pin_path}: Info.plist dictionary value was missing"
                    )));
                }
                _ => {
                    if let Some(field) = pending_field.take() {
                        fields.record(field, ParsedField::Invalid, pin_path)?;
                    }
                    expecting_key = true;
                }
            }
        }
    }
    if depth != 0 || !expecting_key {
        return Err(UpdateError::message(format!(
            "{pin_path}: malformed Info.plist root dictionary"
        )));
    }
    if next_plist_event(&mut reader, &mut event_count, &mut scalar_bytes, pin_path)?.is_some() {
        return Err(UpdateError::message(format!(
            "{pin_path}: Info.plist contained trailing values"
        )));
    }

    let bundle_identifier = fields.required(BundleField::Identifier, pin_path)?;
    let display_name = match fields.optional(BundleField::DisplayName, pin_path)? {
        Some(display_name) if !display_name.is_empty() => display_name,
        _ => fields
            .optional(BundleField::Name, pin_path)?
            .filter(|name| !name.is_empty())
            .ok_or_else(|| {
                UpdateError::message(format!(
                    "{pin_path}: Info.plist missing display name \
                     (CFBundleDisplayName or CFBundleName)"
                ))
            })?,
    };
    let version = fields.required(BundleField::Version, pin_path)?;
    validate_bundle_string(&bundle_identifier, "CFBundleIdentifier", pin_path)?;
    validate_bundle_string(&display_name, "CFBundleDisplayName/CFBundleName", pin_path)?;
    validate_release_version("codex-app bundle", &version)?;
    Ok(BundleIdentity {
        app_name,
        bundle_identifier,
        display_name,
        version,
    })
}

fn validate_bundle_string(value: &str, field: &str, pin_path: &str) -> Result<(), UpdateError> {
    if value.len() <= 256 && !value.chars().any(char::is_control) {
        Ok(())
    } else {
        Err(UpdateError::message(format!(
            "{pin_path}: Info.plist field {field} exceeded its supported format"
        )))
    }
}

impl Default for ParsedBundleFields {
    fn default() -> Self {
        Self {
            identifier: ParsedField::Missing,
            display_name: ParsedField::Missing,
            name: ParsedField::Missing,
            version: ParsedField::Missing,
        }
    }
}

impl ParsedBundleFields {
    fn record(
        &mut self,
        field: BundleField,
        value: ParsedField,
        pin_path: &str,
    ) -> Result<(), UpdateError> {
        let slot = self.slot_mut(field);
        if !matches!(slot, ParsedField::Missing) {
            return Err(UpdateError::message(format!(
                "{pin_path}: Info.plist contained duplicate field {}",
                bundle_field_name(field)
            )));
        }
        *slot = value;
        Ok(())
    }

    fn required(&mut self, field: BundleField, pin_path: &str) -> Result<String, UpdateError> {
        self.optional(field, pin_path)?
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                UpdateError::message(format!(
                    "{pin_path}: Info.plist missing or invalid string field {}",
                    bundle_field_name(field)
                ))
            })
    }

    fn optional(
        &mut self,
        field: BundleField,
        pin_path: &str,
    ) -> Result<Option<String>, UpdateError> {
        match std::mem::replace(self.slot_mut(field), ParsedField::Missing) {
            ParsedField::Missing => Ok(None),
            ParsedField::String(value) => Ok(Some(value)),
            ParsedField::Invalid => Err(UpdateError::message(format!(
                "{pin_path}: Info.plist invalid string field {}",
                bundle_field_name(field)
            ))),
        }
    }

    fn slot_mut(&mut self, field: BundleField) -> &mut ParsedField {
        match field {
            BundleField::Identifier => &mut self.identifier,
            BundleField::DisplayName => &mut self.display_name,
            BundleField::Name => &mut self.name,
            BundleField::Version => &mut self.version,
        }
    }
}

fn bundle_field(key: &str) -> Option<BundleField> {
    match key {
        "CFBundleIdentifier" => Some(BundleField::Identifier),
        "CFBundleDisplayName" => Some(BundleField::DisplayName),
        "CFBundleName" => Some(BundleField::Name),
        "CFBundleShortVersionString" => Some(BundleField::Version),
        _ => None,
    }
}

fn bundle_field_name(field: BundleField) -> &'static str {
    match field {
        BundleField::Identifier => "CFBundleIdentifier",
        BundleField::DisplayName => "CFBundleDisplayName",
        BundleField::Name => "CFBundleName",
        BundleField::Version => "CFBundleShortVersionString",
    }
}

fn next_plist_event<R: std::io::Read + std::io::Seek>(
    reader: &mut PlistReader<R>,
    event_count: &mut usize,
    scalar_bytes: &mut usize,
    pin_path: &str,
) -> Result<Option<PlistEvent<'static>>, UpdateError> {
    let event = reader.next().transpose().map_err(|source| {
        UpdateError::message(format!("{pin_path}: invalid app ZIP Info.plist: {source}"))
    })?;
    let Some(event) = event else {
        return Ok(None);
    };
    *event_count = event_count.checked_add(1).ok_or_else(|| {
        UpdateError::message(format!("{pin_path}: Info.plist event count overflow"))
    })?;
    if *event_count > MAX_PLIST_EVENTS {
        return Err(UpdateError::message(format!(
            "{pin_path}: Info.plist exceeded {MAX_PLIST_EVENTS} events"
        )));
    }
    let bytes = match &event {
        PlistEvent::String(value) => value.len(),
        PlistEvent::Data(value) => value.len(),
        PlistEvent::Boolean(_) => 1,
        PlistEvent::Integer(_) | PlistEvent::Real(_) | PlistEvent::Date(_) | PlistEvent::Uid(_) => {
            16
        }
        _ => 0,
    };
    *scalar_bytes = scalar_bytes
        .checked_add(bytes)
        .filter(|total| *total <= MAX_PLIST_SCALAR_BYTES)
        .ok_or_else(|| {
            UpdateError::message(format!(
                "{pin_path}: Info.plist decoded scalars exceeded \
                 {MAX_PLIST_SCALAR_BYTES} bytes"
            ))
        })?;
    Ok(Some(event))
}

fn require_plist_depth(depth: usize, pin_path: &str) -> Result<(), UpdateError> {
    if depth > MAX_PLIST_DEPTH {
        Err(UpdateError::message(format!(
            "{pin_path}: Info.plist exceeded collection depth {MAX_PLIST_DEPTH}"
        )))
    } else {
        Ok(())
    }
}

fn validate_zip_path(name: &[u8], pin_path: &str) -> Result<(), UpdateError> {
    let components: Vec<_> = name.split(|byte| *byte == b'/').collect();
    if name.is_empty()
        || name.len() > MAX_ZIP_PATH_BYTES
        || name.starts_with(b"/")
        || name.contains(&b'\\')
        || name.contains(&b'\0')
        || name.contains(&b':')
        || name.iter().any(|byte| byte.is_ascii_control())
        || std::str::from_utf8(name).is_err()
        || components.iter().enumerate().any(|(index, component)| {
            matches!(*component, b"." | b"..")
                || (component.is_empty() && index + 1 != components.len())
        })
    {
        return Err(UpdateError::message(format!(
            "{pin_path}: app ZIP contained unsafe path {:?}",
            String::from_utf8_lossy(name)
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::io::Write as _;

    use plist::{Dictionary, Value};
    use rawzip::{CompressionMethod, ZipArchiveWriter};
    use tempfile::NamedTempFile;

    use super::{
        AppcastCandidate, MAX_APPCAST_DEPTH, MAX_PLIST_EVENTS, inspect_bundle, parse_appcast,
        parse_bundle_identity,
    };

    const PIN: &str = "nix/pins/codex-app.json";

    #[test]
    fn representative_appcast_selects_first_full_arm64_item() {
        let fixture = include_bytes!("fixtures/codex-app-appcast.xml");
        assert_eq!(
            parse_appcast(fixture, PIN).expect("representative appcast"),
            AppcastCandidate {
                version: "9.9.9".to_owned(),
                url: "https://persistent.oaistatic.com/codex-app-prod/\
                      ChatGPT-darwin-arm64-9.9.9.zip"
                    .to_owned(),
            }
        );
    }

    #[test]
    fn appcast_namespace_prefix_is_not_significant() {
        let fixture = br#"
            <rss xmlns:release="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
              <release:shortVersionString>1.2.3</release:shortVersionString>
              <release:hardwareRequirements>arm64</release:hardwareRequirements>
              <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip"/>
            </item></channel></rss>
        "#;
        assert_eq!(
            parse_appcast(fixture, PIN).expect("alternate namespace prefix"),
            AppcastCandidate {
                version: "1.2.3".to_owned(),
                url: "https://persistent.oaistatic.com/codex-app-prod/\
                      ChatGPT-darwin-arm64-1.2.3.zip"
                    .to_owned(),
            }
        );
    }

    #[test]
    fn appcast_rejects_malformed_missing_and_ambiguous_candidates() {
        assert!(parse_appcast(b"<rss>", PIN).is_err());
        assert!(parse_appcast(b"<rss><channel/></rss>", PIN).is_err());
        let ambiguous = br#"
            <rss><channel><item>
              <title>1.2.3</title>
              <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip"/>
              <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip"/>
            </item></channel></rss>
        "#;
        assert!(parse_appcast(ambiguous, PIN).is_err());

        let wrong_namespace = br#"
            <rss xmlns:sparkle="https://example.invalid/not-sparkle"><channel><item>
              <title></title>
              <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
              <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip"/>
            </item></channel></rss>
        "#;
        assert!(parse_appcast(wrong_namespace, PIN).is_err());

        for invalid in [
            br#"<rss><channel><item><title>1.2.3</title><enclosure url="file:///tmp/ChatGPT-darwin-arm64-1.2.3.zip"/></item></channel></rss>"#
                .as_slice(),
            br#"<rss><channel><item><title>1.2.3</title><enclosure url="https://example.invalid/ChatGPT-darwin-arm64-1.2.3.zip"/></item></channel></rss>"#
                .as_slice(),
            br#"<rss><channel><item><title>not-a-version</title><enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-not-a-version.zip"/></item></channel></rss>"#
                .as_slice(),
            br#"<rss><wrapper><channel><item><title>1.2.3</title><enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip"/></item></channel></wrapper></rss>"#
                .as_slice(),
            br#"<rss></rss><rss></rss>"#.as_slice(),
        ] {
            assert!(parse_appcast(invalid, PIN).is_err());
        }
    }

    #[test]
    fn appcast_uses_title_fallback_and_ignores_nested_deltas() {
        let fixture = br#"
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel><item>
                <title>1.2.3</title>
                <sparkle:deltas>
                  <enclosure url="https://example.invalid/delta-darwin-arm64.zip"/>
                </sparkle:deltas>
                <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip"/>
              </item></channel>
            </rss>
        "#;
        assert_eq!(
            parse_appcast(fixture, PIN).expect("title fallback"),
            AppcastCandidate {
                version: "1.2.3".to_owned(),
                url: "https://persistent.oaistatic.com/codex-app-prod/\
                      ChatGPT-darwin-arm64-1.2.3.zip"
                    .to_owned(),
            }
        );
    }

    #[test]
    fn appcast_ignores_non_candidates_and_later_item_details() {
        let fixture = br#"
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item>
                  <title>1.2.2</title>
                  <sparkle:hardwareRequirements>x86_64</sparkle:hardwareRequirements>
                  <enclosure/>
                </item>
                <item>
                  <title>1.2.3</title>
                  <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip"/>
                </item>
                <item>
                  <title>1.2.4</title>
                  <enclosure/>
                </item>
              </channel>
            </rss>
        "#;
        assert_eq!(
            parse_appcast(fixture, PIN).expect("first eligible item"),
            AppcastCandidate {
                version: "1.2.3".to_owned(),
                url: "https://persistent.oaistatic.com/codex-app-prod/\
                      ChatGPT-darwin-arm64-1.2.3.zip"
                    .to_owned(),
            }
        );
    }

    #[test]
    fn appcast_bounds_depth_without_copying_large_namespace_uris() {
        let large_namespace = "x".repeat(1024 * 1024);
        let fixture = format!(
            r#"<rss xmlns:unused="{large_namespace}"><channel><item>
                <title>1.2.3</title>
                <enclosure url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip"/>
            </item></channel></rss>"#
        );
        assert!(parse_appcast(fixture.as_bytes(), PIN).is_ok());

        let nested = format!(
            "<rss>{}<channel/></rss>",
            "<wrapper>".repeat(MAX_APPCAST_DEPTH)
        );
        assert!(
            parse_appcast(nested.as_bytes(), PIN)
                .expect_err("excessive XML depth")
                .to_string()
                .contains("XML depth")
        );
    }

    #[test]
    fn bundle_identity_supports_xml_stored_and_binary_deflated_plists() {
        for (binary, compression) in [
            (false, CompressionMethod::STORE),
            (true, CompressionMethod::DEFLATE),
        ] {
            let plist = valid_plist(Some(Value::String("Codex".to_owned())));
            let bytes = plist_bytes(&plist, binary);
            let archive = zip_file(
                &[("Codex.app/Contents/Info.plist", bytes.as_slice())],
                compression,
            );
            let identity = inspect_bundle(archive.path(), PIN).expect("valid app archive");
            assert_eq!(identity.app_name, "Codex.app");
            assert_eq!(identity.bundle_identifier, "com.example.Codex");
            assert_eq!(identity.display_name, "Codex");
            assert_eq!(identity.version, "1.2.3");
        }
    }

    #[test]
    fn bundle_identity_falls_back_only_for_missing_or_empty_display_name() {
        for display_name in [None, Some(Value::String(String::new()))] {
            let plist = valid_plist(display_name);
            let bytes = plist_bytes(&plist, false);
            let archive = zip_file(
                &[("Codex.app/Contents/Info.plist", bytes.as_slice())],
                CompressionMethod::STORE,
            );
            let identity = inspect_bundle(archive.path(), PIN).expect("display-name fallback");
            assert_eq!(identity.display_name, "Codex Fallback");
        }

        let plist = valid_plist(Some(Value::Boolean(true)));
        let bytes = plist_bytes(&plist, false);
        let archive = zip_file(
            &[("Codex.app/Contents/Info.plist", bytes.as_slice())],
            CompressionMethod::STORE,
        );
        assert!(
            inspect_bundle(archive.path(), PIN)
                .expect_err("non-string display name")
                .to_string()
                .contains("CFBundleDisplayName")
        );

        let mut plist = valid_plist(Some(Value::String("Codex".to_owned())));
        plist
            .as_dictionary_mut()
            .expect("dictionary")
            .insert("CFBundleName".to_owned(), Value::Boolean(true));
        let bytes = plist_bytes(&plist, false);
        let archive = zip_file(
            &[("Codex.app/Contents/Info.plist", bytes.as_slice())],
            CompressionMethod::STORE,
        );
        let identity =
            inspect_bundle(archive.path(), PIN).expect("unused fallback may be non-string");
        assert_eq!(identity.display_name, "Codex");
    }

    #[test]
    fn bundle_identity_rejects_missing_duplicate_nested_and_unsafe_plists() {
        let valid = plist_bytes(&valid_plist(None), false);
        for entries in [
            vec![("README", b"not a plist".as_slice())],
            vec![("Payload/Codex.app/Contents/Info.plist", valid.as_slice())],
            vec![(".app/Contents/Info.plist", valid.as_slice())],
        ] {
            let archive = zip_file(&entries, CompressionMethod::STORE);
            assert!(inspect_bundle(archive.path(), PIN).is_err());
        }

        let duplicate = zip_file(
            &[
                ("Codex.app/Contents/Info.plist", valid.as_slice()),
                ("Codex.app/Contents/Info.plist", valid.as_slice()),
            ],
            CompressionMethod::STORE,
        );
        assert!(
            inspect_bundle(duplicate.path(), PIN)
                .expect_err("duplicate manifest path")
                .to_string()
                .contains("duplicate entry path")
        );

        let multiple = zip_file(
            &[
                ("Codex.app/Contents/Info.plist", valid.as_slice()),
                ("Other.app/Contents/Info.plist", valid.as_slice()),
            ],
            CompressionMethod::STORE,
        );
        assert!(
            inspect_bundle(multiple.path(), PIN)
                .expect_err("multiple app bundles")
                .to_string()
                .contains("multiple top-level")
        );

        for (safe_name, unsafe_name) in [
            (
                "xx/Codex.app/Contents/Info.plist",
                "../Codex.app/Contents/Info.plist",
            ),
            (
                "Codex.app/Contents/Info.plist",
                r"Codex.app\Contents/Info.plist",
            ),
            (
                "XCodex.app/Contents/Info.plist",
                "/Codex.app/Contents/Info.plist",
            ),
            (
                "Codex.app/xContents/Info.plist",
                "Codex.app//Contents/Info.plist",
            ),
        ] {
            let archive = zip_file(&[(safe_name, valid.as_slice())], CompressionMethod::STORE);
            replace_archive_bytes(archive.path(), safe_name.as_bytes(), unsafe_name.as_bytes());
            assert!(
                inspect_bundle(archive.path(), PIN)
                    .expect_err("unsafe path")
                    .to_string()
                    .contains("unsafe path")
            );
        }
    }

    #[test]
    fn bundle_identity_rejects_malformed_oversized_and_incomplete_plists() {
        let malformed = zip_file(
            &[("Codex.app/Contents/Info.plist", b"not a plist")],
            CompressionMethod::STORE,
        );
        assert!(inspect_bundle(malformed.path(), PIN).is_err());

        let oversized = vec![b'x'; super::MAX_PLIST_BYTES as usize + 1];
        let oversized_archive = zip_file(
            &[("Codex.app/Contents/Info.plist", oversized.as_slice())],
            CompressionMethod::DEFLATE,
        );
        assert!(
            inspect_bundle(oversized_archive.path(), PIN)
                .expect_err("oversized plist")
                .to_string()
                .contains("exceeded")
        );

        let mut incomplete = valid_plist(None);
        incomplete
            .as_dictionary_mut()
            .expect("dictionary")
            .remove("CFBundleIdentifier");
        let incomplete_bytes = plist_bytes(&incomplete, false);
        let incomplete_archive = zip_file(
            &[("Codex.app/Contents/Info.plist", incomplete_bytes.as_slice())],
            CompressionMethod::STORE,
        );
        assert!(
            inspect_bundle(incomplete_archive.path(), PIN)
                .expect_err("missing identity")
                .to_string()
                .contains("CFBundleIdentifier")
        );
    }

    #[test]
    fn bundle_identity_rejects_local_header_mismatch_and_bad_crc() {
        let valid = plist_bytes(&valid_plist(Some(Value::String("Codex".to_owned()))), false);
        let local_mismatch = zip_file(
            &[("Codex.app/Contents/Info.plist", valid.as_slice())],
            CompressionMethod::STORE,
        );
        replace_first_archive_bytes(
            local_mismatch.path(),
            b"Codex.app/Contents/Info.plist",
            b"Other.app/Contents/Info.plist",
        );
        assert!(
            inspect_bundle(local_mismatch.path(), PIN)
                .expect_err("local filename mismatch")
                .to_string()
                .contains("local header")
        );

        let bad_crc = zip_file(
            &[("Codex.app/Contents/Info.plist", valid.as_slice())],
            CompressionMethod::STORE,
        );
        let mut bytes = std::fs::read(bad_crc.path()).expect("read CRC fixture");
        let identity = bytes
            .windows(b"com.example.Codex".len())
            .position(|candidate| candidate == b"com.example.Codex")
            .expect("plist identity in stored entry");
        bytes[identity + b"com.example.Code".len()] = b'y';
        std::fs::write(bad_crc.path(), bytes).expect("write CRC fixture");
        assert!(
            inspect_bundle(bad_crc.path(), PIN)
                .expect_err("CRC mismatch")
                .to_string()
                .contains("verify")
        );
    }

    #[test]
    fn bundle_identity_allows_unrelated_symlinks_but_rejects_symlinked_plist() {
        let valid = plist_bytes(&valid_plist(None), false);
        let with_unrelated_symlink = zip_file(
            &[
                ("Codex.app/Contents/Info.plist", valid.as_slice()),
                ("Codex.app/Current", b"Versions/A"),
            ],
            CompressionMethod::STORE,
        );
        set_central_unix_mode(
            with_unrelated_symlink.path(),
            b"Codex.app/Current",
            0o120_777,
        );
        inspect_bundle(with_unrelated_symlink.path(), PIN).expect("unrelated app symlink");

        let symlinked_plist = zip_file(
            &[("Codex.app/Contents/Info.plist", valid.as_slice())],
            CompressionMethod::STORE,
        );
        set_central_unix_mode(
            symlinked_plist.path(),
            b"Codex.app/Contents/Info.plist",
            0o120_777,
        );
        assert!(
            inspect_bundle(symlinked_plist.path(), PIN)
                .expect_err("symlinked plist")
                .to_string()
                .contains("not a regular file")
        );
    }

    #[test]
    fn bundle_identity_bounds_streamed_plist_events_and_scalar_bytes() {
        let mut too_many_events = valid_plist(None);
        too_many_events
            .as_dictionary_mut()
            .expect("dictionary")
            .insert(
                "Noise".to_owned(),
                Value::Array(vec![Value::Boolean(true); MAX_PLIST_EVENTS]),
            );
        let bytes = plist_bytes(&too_many_events, true);
        assert!(
            parse_bundle_identity(&bytes, "Codex.app".to_owned(), PIN)
                .expect_err("too many plist events")
                .to_string()
                .contains("events")
        );

        let repeated = Value::String("x".repeat(100 * 1024));
        let mut too_many_scalar_bytes = valid_plist(None);
        too_many_scalar_bytes
            .as_dictionary_mut()
            .expect("dictionary")
            .insert("Noise".to_owned(), Value::Array(vec![repeated; 50]));
        let bytes = plist_bytes(&too_many_scalar_bytes, true);
        assert!(
            parse_bundle_identity(&bytes, "Codex.app".to_owned(), PIN)
                .expect_err("too many decoded scalar bytes")
                .to_string()
                .contains("decoded scalars")
        );
    }

    fn valid_plist(display_name: Option<Value>) -> Value {
        let mut dictionary = Dictionary::new();
        dictionary.insert(
            "CFBundleIdentifier".to_owned(),
            Value::String("com.example.Codex".to_owned()),
        );
        dictionary.insert(
            "CFBundleName".to_owned(),
            Value::String("Codex Fallback".to_owned()),
        );
        dictionary.insert(
            "CFBundleShortVersionString".to_owned(),
            Value::String("1.2.3".to_owned()),
        );
        if let Some(display_name) = display_name {
            dictionary.insert("CFBundleDisplayName".to_owned(), display_name);
        }
        Value::Dictionary(dictionary)
    }

    fn plist_bytes(plist: &Value, binary: bool) -> Vec<u8> {
        let mut bytes = Vec::new();
        if binary {
            plist
                .to_writer_binary(&mut bytes)
                .expect("serialize binary plist");
        } else {
            plist
                .to_writer_xml(&mut bytes)
                .expect("serialize XML plist");
        }
        bytes
    }

    fn zip_file(entries: &[(&str, &[u8])], compression: CompressionMethod) -> NamedTempFile {
        let archive = NamedTempFile::new().expect("temporary ZIP");
        let file = archive.reopen().expect("reopen temporary ZIP");
        let mut writer = ZipArchiveWriter::new(file);
        for (name, contents) in entries {
            let (mut entry, config) = writer
                .new_file(name)
                .compression_method(compression)
                .start()
                .expect("start ZIP entry");
            match compression {
                CompressionMethod::STORE => {
                    let mut contents_writer = config.wrap(&mut entry);
                    contents_writer
                        .write_all(contents)
                        .expect("write stored ZIP entry");
                    let (_, descriptor) = contents_writer.finish().expect("finish stored contents");
                    entry.finish(descriptor).expect("finish stored ZIP entry");
                }
                CompressionMethod::DEFLATE => {
                    let encoder = flate2::write::DeflateEncoder::new(
                        &mut entry,
                        flate2::Compression::default(),
                    );
                    let mut contents_writer = config.wrap(encoder);
                    contents_writer
                        .write_all(contents)
                        .expect("write deflated ZIP entry");
                    let (encoder, descriptor) =
                        contents_writer.finish().expect("finish deflated contents");
                    encoder.finish().expect("finish deflate stream");
                    entry.finish(descriptor).expect("finish deflated ZIP entry");
                }
                _ => panic!("unsupported test compression"),
            }
        }
        writer.finish().expect("finish ZIP");
        archive
    }

    fn replace_archive_bytes(path: &std::path::Path, before: &[u8], after: &[u8]) {
        assert_eq!(before.len(), after.len());
        let mut bytes = std::fs::read(path).expect("read ZIP for mutation");
        let positions: Vec<_> = bytes
            .windows(before.len())
            .enumerate()
            .filter_map(|(offset, candidate)| (candidate == before).then_some(offset))
            .collect();
        assert_eq!(positions.len(), 2, "local and central names");
        for offset in positions {
            bytes[offset..offset + after.len()].copy_from_slice(after);
        }
        std::fs::write(path, bytes).expect("write mutated ZIP");
    }

    fn replace_first_archive_bytes(path: &std::path::Path, before: &[u8], after: &[u8]) {
        assert_eq!(before.len(), after.len());
        let mut bytes = std::fs::read(path).expect("read ZIP for mutation");
        let offset = bytes
            .windows(before.len())
            .position(|candidate| candidate == before)
            .expect("archive bytes to replace");
        bytes[offset..offset + after.len()].copy_from_slice(after);
        std::fs::write(path, bytes).expect("write mutated ZIP");
    }

    fn set_central_unix_mode(path: &std::path::Path, name: &[u8], mode: u32) {
        let mut bytes = std::fs::read(path).expect("read ZIP for mode mutation");
        let name_offset = bytes
            .windows(name.len())
            .enumerate()
            .find_map(|(offset, candidate)| {
                (candidate == name
                    && offset >= 46
                    && bytes[offset - 46..offset - 42] == *b"PK\x01\x02")
                    .then_some(offset)
            })
            .expect("central directory name");
        let header_offset = name_offset - 46;
        bytes[header_offset + 5] = 3;
        bytes[header_offset + 38..header_offset + 42].copy_from_slice(&(mode << 16).to_le_bytes());
        std::fs::write(path, bytes).expect("write ZIP mode mutation");
    }
}
