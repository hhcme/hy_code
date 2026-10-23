//! Bounded SVG rasterization. No image/resource URLs, scripts, or file access
//! from SVG. Optional platform font discovery is cached once on the worker.
use crate::{HyCodeBuffer, WorkspaceError};
use resvg::{tiny_skia, usvg};
use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    ptr, slice,
    sync::{Arc, OnceLock},
};

const MAX_BYTES: usize = 2 * 1024 * 1024;
const MAX_SIDE: u32 = 4096;
static FONTS: OnceLock<Arc<usvg::fontdb::Database>> = OnceLock::new();

#[repr(C)]
pub struct HyCodeImageResult {
    pub pixels: HyCodeBuffer,
    pub error: HyCodeBuffer,
    pub width: u32,
    pub height: u32,
    pub source_width: f64,
    pub source_height: f64,
}
fn empty() -> HyCodeBuffer {
    HyCodeBuffer {
        data: ptr::null_mut(),
        len: 0,
    }
}
fn buffer(bytes: Vec<u8>) -> HyCodeBuffer {
    if bytes.is_empty() {
        return empty();
    }
    let mut bytes = bytes.into_boxed_slice();
    let result = HyCodeBuffer {
        data: bytes.as_mut_ptr(),
        len: bytes.len(),
    };
    std::mem::forget(bytes);
    result
}
fn failure(message: &str) -> WorkspaceError {
    WorkspaceError::new("svg_preview", message)
}
fn rasterize(
    bytes: &[u8],
    edge: u32,
    system_fonts: bool,
) -> Result<HyCodeImageResult, WorkspaceError> {
    if bytes.len() > MAX_BYTES || edge == 0 || edge > MAX_SIDE {
        return Err(failure("SVG 大小或预览尺寸超出限制"));
    }
    let text = std::str::from_utf8(bytes).map_err(|_| failure("SVG 需要有效的 UTF-8 编码"))?;
    let xml = roxmltree::Document::parse_with_options(
        text,
        roxmltree::ParsingOptions {
            allow_dtd: false,
            nodes_limit: 4_096,
            ..Default::default()
        },
    )
    .map_err(|_| failure("SVG 无效、包含 DTD 或节点过多"))?;
    let mut has_text = false;
    let mut path_bytes = 0usize;
    let mut text_bytes = 0usize;
    for node in xml.descendants().filter(|n| n.is_element()) {
        if node.ancestors().take(130).count() > 128 {
            return Err(failure("SVG 层级过深"));
        }
        let tag = node.tag_name().name();
        if matches!(
            tag,
            "script"
                | "foreignObject"
                | "image"
                | "use"
                | "filter"
                | "mask"
                | "pattern"
                | "clipPath"
                | "marker"
                | "tref"
        ) {
            return Err(failure(
                "当前 SVG 预览不支持脚本、外部内容、use、滤镜、蒙版、图案或裁剪路径",
            ));
        }
        if node
            .attributes()
            .any(|a| a.name() == "href" && !a.value().starts_with('#'))
        {
            return Err(failure("SVG 外部资源不在当前预览范围内"));
        }
        for attribute in node.attributes() {
            if matches!(attribute.name(), "d" | "points") {
                path_bytes += attribute.value().len();
            }
        }
        if matches!(tag, "text" | "style") {
            text_bytes += node
                .descendants()
                .filter_map(|n| n.text().filter(|_| n.is_text()))
                .map(str::len)
                .sum::<usize>();
        }
        if path_bytes > 131_072 || text_bytes > 2_048 {
            return Err(failure("SVG 路径或文字复杂度超出预览限制"));
        }
        has_text |= tag == "text";
    }
    let mut options = usvg::Options {
        image_href_resolver: usvg::ImageHrefResolver {
            resolve_data: Box::new(|_, _, _| None),
            resolve_string: Box::new(|_, _| None),
        },
        ..Default::default()
    };
    if has_text && system_fonts {
        options.fontdb = FONTS
            .get_or_init(|| {
                let mut fonts = usvg::fontdb::Database::new();
                fonts.load_system_fonts();
                Arc::new(fonts)
            })
            .clone();
    }
    let tree =
        usvg::Tree::from_xmltree(&xml, &options).map_err(|_| failure("无法解析 SVG 图形"))?;
    let size = tree.size();
    let (sw, sh) = (f64::from(size.width()), f64::from(size.height()));
    if !sw.is_finite() || !sh.is_finite() || sw.max(sh) > 65_535.0 {
        return Err(failure("SVG 画布尺寸超出限制"));
    }
    let scale = f64::from(edge) / sw.max(sh);
    let w = (sw * scale).round().clamp(1.0, f64::from(edge)) as u32;
    let h = (sh * scale).round().clamp(1.0, f64::from(edge)) as u32;
    // Budget the converted render tree, including isolation introduced by CSS
    // or text flattening. The output edge alone does not bound group buffers.
    let transform =
        tiny_skia::Transform::from_scale((f64::from(w) / sw) as f32, (f64::from(h) / sh) as f32);
    validate_layers(tree.root(), transform, &mut (0, 0, 0))?;
    let mut pixmap = tiny_skia::Pixmap::new(w, h).ok_or_else(|| failure("SVG 预览分配失败"))?;
    resvg::render(
        &tree,
        tiny_skia::Transform::from_scale((f64::from(w) / sw) as f32, (f64::from(h) / sh) as f32),
        &mut pixmap.as_mut(),
    );
    Ok(HyCodeImageResult {
        pixels: buffer(pixmap.take()),
        error: empty(),
        width: w,
        height: h,
        source_width: sw,
        source_height: sh,
    })
}
fn validate_layers(
    group: &usvg::Group,
    parent: tiny_skia::Transform,
    budget: &mut (u64, usize, usize),
) -> Result<(), WorkspaceError> {
    if !group.filters().is_empty() || group.mask().is_some() || group.clip_path().is_some() {
        return Err(failure("SVG 效果超出当前预览范围"));
    }
    let transform = parent.pre_concat(group.transform());
    if group.should_isolate() {
        let bbox = group
            .layer_bounding_box()
            .transform(transform)
            .ok_or_else(|| failure("SVG 图层尺寸无效"))?;
        let area = (f64::from(bbox.width()).ceil() + 4.0) * (f64::from(bbox.height()).ceil() + 4.0);
        if !area.is_finite() || area > 8_000_000.0 {
            return Err(failure("SVG 图层超出预览预算"));
        }
        budget.0 += area as u64;
        if budget.0 > 8_000_000 {
            return Err(failure("SVG 累计图层超出预览预算"));
        }
    }
    for node in group.children() {
        budget.1 += 1;
        if budget.1 > 8_192 {
            return Err(failure("SVG 渲染节点过多"));
        }
        match node {
            usvg::Node::Group(child) => validate_layers(child, transform, budget)?,
            usvg::Node::Text(text) => validate_layers(text.flattened(), transform, budget)?,
            usvg::Node::Path(path) => {
                budget.2 += path.data().segments().count();
                if budget.2 > 100_000 {
                    return Err(failure("SVG 路径段过多"));
                }
            }
            usvg::Node::Image(_) => return Err(failure("SVG 嵌入图像不在当前范围内")),
        }
    }
    Ok(())
}

/// # Safety
/// Non-null data points to `len` readable bytes for this call. Caller frees both
/// buffers exactly once with hycode_buffer_free. No retained input or callbacks.
/// Background-only; concurrent calls are independent, optional font cache shared
/// immutably. Cancellation is checked by the host before/after this synchronous call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hycode_svg_render(
    data: *const u8,
    len: usize,
    edge: u32,
    system_fonts: bool,
) -> HyCodeImageResult {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if data.is_null() || len == 0 || len > MAX_BYTES {
            return Err(failure("SVG 数据为空或超过 2 MiB"));
        }
        rasterize(
            unsafe { slice::from_raw_parts(data, len) },
            edge,
            system_fonts,
        )
    }))
    .unwrap_or_else(|_| Err(failure("SVG 渲染失败")));
    match result {
        Ok(value) => value,
        Err(error) => HyCodeImageResult {
            pixels: empty(),
            error: buffer(serde_json::to_vec(&error).unwrap_or_default()),
            width: 0,
            height: 0,
            source_width: 0.0,
            source_height: 0.0,
        },
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::hycode_buffer_free;
    #[test]
    fn svg_renders_premultiplied_pixels_and_preserves_aspect() {
        let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="red" fill-opacity=".5"/></svg>"#;
        unsafe {
            let result = hycode_svg_render(svg.as_ptr(), svg.len(), 80, false);
            assert_eq!(
                (result.width, result.height, result.source_width),
                (80, 40, 40.0)
            );
            assert!(result.error.data.is_null());
            let pixels = slice::from_raw_parts(result.pixels.data, result.pixels.len);
            assert_eq!(pixels.len(), 80 * 40 * 4);
            assert!((126..=129).contains(&pixels[3]));
            assert_eq!(pixels[0], pixels[3]);
            hycode_buffer_free(result.pixels);
            hycode_buffer_free(result.error);
        }
    }
    #[test]
    fn svg_rejects_malformed_external_active_and_oversized_input() {
        for svg in [
            "broken",
            "<!DOCTYPE svg><svg/>",
            "<svg xmlns='http://www.w3.org/2000/svg'><image href='/tmp/private.png'/></svg>",
            "<svg xmlns='http://www.w3.org/2000/svg'><script>test()</script></svg>",
            "<svg xmlns='http://www.w3.org/2000/svg' width='1000000' height='20'/>",
        ] {
            unsafe {
                let r = hycode_svg_render(svg.as_ptr(), svg.len(), 64, false);
                assert!(r.pixels.data.is_null());
                assert!(!r.error.data.is_null());
                hycode_buffer_free(r.pixels);
                hycode_buffer_free(r.error);
            }
        }
    }
    #[test]
    fn svg_budgets_isolation_and_rejects_filters_or_use_before_rendering() {
        let nested = format!(
            "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'>{}<rect width='40' height='40'/>{}</svg>",
            "<g opacity='.5'>".repeat(120),
            "</g>".repeat(120)
        );
        assert!(rasterize(nested.as_bytes(), 2048, false).is_err());
        for svg in [
            "<svg xmlns='http://www.w3.org/2000/svg'><defs><filter id='f'><feFlood/></filter></defs></svg>",
            "<svg xmlns='http://www.w3.org/2000/svg'><use href='#a'/></svg>",
            "<svg xmlns='http://www.w3.org/2000/svg'><marker id='m'><rect width='1' height='1'/></marker></svg>",
            "<svg xmlns='http://www.w3.org/2000/svg'><text><tref href='#t'/></text></svg>",
        ] {
            assert!(rasterize(svg.as_bytes(), 64, false).is_err());
        }
    }
    #[test]
    fn svg_ffi_rejects_invalid_buffers_and_dimensions() {
        let svg = b"<svg xmlns='http://www.w3.org/2000/svg' width='1' height='1'/>";
        for (data, len, edge) in [
            (ptr::null(), 4, 1),
            (svg.as_ptr(), svg.len(), 0),
            (svg.as_ptr(), svg.len(), 4097),
            (svg.as_ptr(), MAX_BYTES + 1, 32),
        ] {
            unsafe {
                let r = hycode_svg_render(data, len, edge, false);
                assert!(r.width == 0 && !r.error.data.is_null());
                hycode_buffer_free(r.error);
                hycode_buffer_free(r.pixels);
            }
        }
    }
}
