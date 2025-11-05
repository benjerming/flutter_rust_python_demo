use std::path::{Path, PathBuf};

#[allow(unused_imports)]
use log::{info, warn};

/// A [Name Record](https://docs.microsoft.com/en-us/typography/opentype/spec/name#name-records).
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Name {
    /// A platform ID.
    pub platform_id: usize,
    /// A platform-specific encoding ID.
    pub encoding_id: u16,
    /// A language ID.
    pub language_id: u16,
    /// A [Name ID]
    pub name_id: u16,
    /// A raw name data. Can be in any encoding. Can be empty.
    pub raw_name: Vec<u8>,
    /// convient name in utf-8 encoding
    pub utf8_name: String,
}

impl From<ttf_parser::name::Name<'_>> for Name {
    fn from(name: ttf_parser::name::Name<'_>) -> Self {
        Self {
            platform_id: name.platform_id as usize,
            encoding_id: name.encoding_id.into(),
            language_id: name.language_id.into(),
            name_id: name.name_id.into(),
            raw_name: name.name.to_vec(),
            utf8_name: String::from_utf8_lossy(name.name).to_string(),
        }
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Face {
    pub path: String,
    pub index: u32,
    pub family: String,
    pub style: String,
    pub full_name: String,
    pub post_script_name: String,
    pub bold: bool,
    pub italic: bool,
    pub names: Vec<Name>,
}

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Font {
    pub path: String,
    pub faces: Vec<Face>,
}

impl TryFrom<&PathBuf> for Font {
    type Error = String;
    fn try_from(path: &PathBuf) -> Result<Self, Self::Error> {
        Self::parse_font_file(&path)
    }
}

impl TryFrom<&Path> for Font {
    type Error = String;
    fn try_from(path: &Path) -> Result<Self, Self::Error> {
        Self::parse_font_file(path)
    }
}

impl Font {
    fn parse_font_file(font_path: &Path) -> Result<Font, String> {
        let font_data = std::fs::read(font_path).map_err(|e| format!("读取文件失败: {}", e))?;
        let face_count = ttf_parser::fonts_in_collection(&font_data).unwrap_or(1);

        if face_count == 0 {
            return Err("字体集合不包含任何字体面".to_string());
        }

        let mut faces = Vec::<Face>::new();
        for index in 0..face_count {
            let face = ttf_parser::Face::parse(&font_data, index)
                .map_err(|e| format!("解析字体数据失败: {:?}", e))?;

            Self::inspect_names(&face);
            let (family, style, full_name, post_script_name, bold, italic) =
                Self::extract_common_name_attr(&face)
                    .map_err(|e| format!("{e} at index={index} of font={font_path:?}"))?;

            let names = Self::extract_names(&face);

            faces.push(Face {
                path: font_path.to_string_lossy().to_string(),
                index,
                family,
                style,
                full_name,
                post_script_name,
                bold,
                italic,
                names,
            });
        }

        Ok(Font {
            path: font_path.to_string_lossy().to_string(),
            faces,
        })
    }

    fn extract_names(face: &ttf_parser::Face) -> Vec<Name> {
        face.names()
            .into_iter()
            .map(|name| Name::from(name))
            .collect()
    }

    fn extract_common_name_attr(
        face: &ttf_parser::Face,
    ) -> Result<(String, String, String, String, bool, bool), String> {
        let mut family = None;
        let mut style = None;
        let mut full_name = None;
        let mut post_script_name = None;

        for name in face.names() {
            match name.name_id {
                ttf_parser::name_id::FAMILY | ttf_parser::name_id::TYPOGRAPHIC_FAMILY => {
                    let _ = family.insert(String::from_utf8_lossy(name.name).to_string());
                }
                ttf_parser::name_id::SUBFAMILY => {
                    let _ = style.insert(String::from_utf8_lossy(name.name).to_string());
                }
                ttf_parser::name_id::FULL_NAME => {
                    let _ = full_name.insert(String::from_utf8_lossy(name.name).to_string());
                }
                ttf_parser::name_id::POST_SCRIPT_NAME => {
                    let _ = post_script_name.insert(String::from_utf8_lossy(name.name).to_string());
                }
                _ => {}
            }
        }

        let family = family.ok_or("No family_id".to_string())?;
        let style = style.ok_or("No style_id".to_string())?;
        let full_name = full_name.ok_or("No full_name".to_string())?;
        let post_script_name = post_script_name.ok_or("No post_script_name".to_string())?;
        let bold = Self::is_bold_font(face);
        let italic = Self::is_italic_font(face);
        Ok((family, style, full_name, post_script_name, bold, italic))
    }

    /// 判断是否为粗体字体
    fn is_bold_font(face: &ttf_parser::Face) -> bool {
        let weight = face.weight();
        weight.to_number() >= 600
    }

    /// 判断是否为斜体字体
    fn is_italic_font(face: &ttf_parser::Face) -> bool {
        matches!(
            face.style(),
            ttf_parser::Style::Italic | ttf_parser::Style::Oblique
        )
    }

    fn inspect_names(face: &ttf_parser::Face) {
        for name in face.names() {
            println!("name: {:?}", name);
        }
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Fonts {
    pub fonts: Vec<Font>,
}

#[allow(dead_code)]
impl Fonts {
    pub fn from_dir<P>(dir: P) -> Result<Self, String>
    where
        P: AsRef<Path>,
    {
        let directory = dir.as_ref();
        if !directory.exists() {
            return Err(format!("directory={directory:?} not exists"));
        }

        if !directory.is_dir() {
            return Err(format!("directory={directory:?} is not a directory"));
        }

        let files = Self::collect_font_files(directory);
        let fonts = files
            .into_iter()
            .map(|path| Font::parse_font_file(&path))
            .inspect(|res| {
                if let Err(e) = res {
                    warn!("{e:?}");
                }
            })
            .filter_map(|res| res.ok())
            .collect();
        Ok(Self { fonts })
    }

    fn collect_font_files(directory: &Path) -> Vec<std::path::PathBuf> {
        let mut font_files = Vec::new();
        Self::collect_font_files_impl(directory, &mut font_files);
        font_files
    }

    fn collect_font_files_impl(directory: &Path, font_files: &mut Vec<std::path::PathBuf>) {
        let entries = match std::fs::read_dir(directory) {
            Ok(entries) => entries,
            Err(e) => {
                warn!("无法读取目录 {:?}: {}", directory, e);
                return;
            }
        };

        for entry in entries.flatten() {
            let path = entry.path();

            if path.is_dir() {
                Self::collect_font_files_impl(&path, font_files);
            } else if path.is_file() && Self::is_font_file(&path) {
                font_files.push(path);
            }
        }
    }

    /// 检查是否为字体文件
    fn is_font_file(path: &Path) -> bool {
        if let Some(extension) = path.extension() {
            if let Some(ext_str) = extension.to_str() {
                let ext_lower = ext_str.to_lowercase();
                return matches!(ext_lower.as_str(), "ttf" | "otf" | "ttc" | "otc");
            }
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_font_file() {
        let font = Font::try_from(Path::new(
            "D:/PdfConvertFonts/androidfonts/NotoSansCJK-Regular.ttc",
        ))
        .unwrap();
        println!("{:?}", font);
        assert_eq!(
            font.path,
            "D:/PdfConvertFonts/androidfonts/NotoSansCJK-Regular.ttc"
        );
    }
}
