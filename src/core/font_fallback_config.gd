class_name FontFallbackConfig
extends RefCounted
## Configures font fallbacks for non-Latin scripts
## (CJK, Arabic, Devanagari, Thai). Loads Noto Sans
## variants from assets/fonts/noto/ and adds them as
## fallbacks on the primary fonts used in themes.
##
## Place these files in assets/fonts/noto/:
##   NotoSansSC-Regular.ttf  (Simplified Chinese)
##   NotoSansJP-Regular.ttf  (Japanese)
##   NotoSansKR-Regular.ttf  (Korean)
##   NotoSansArabic-Regular.ttf
##   NotoSansDevanagari-Regular.ttf  (Hindi)
##   NotoSansThai-Regular.ttf


const _NOTO_FONT_DIR := (
	"res://assets/fonts/noto/")
const _HUD_THEME_PATH := (
	"res://src/ui/hud_theme.tres")

const _FALLBACK_FILES := [
	"NotoSansSC-Regular.ttf",
	"NotoSansJP-Regular.ttf",
	"NotoSansKR-Regular.ttf",
	"NotoSansArabic-Regular.ttf",
	"NotoSansDevanagari-Regular.ttf",
	"NotoSansThai-Regular.ttf",
]


## Call once at startup to add Noto Sans fallbacks
## to all theme fonts. Silently skips missing files.
static func configure_fallbacks() -> void:
	var fallback_fonts: Array[Font] = []
	for file_name in _FALLBACK_FILES:
		var path: String = _NOTO_FONT_DIR + file_name
		if not ResourceLoader.exists(path):
			continue
		var font: FontFile = load(path)
		if font != null:
			fallback_fonts.append(font)

	if fallback_fonts.is_empty():
		return

	# Add fallbacks to the primary theme fonts.
	_add_fallbacks_to_theme(
		G.settings.default_theme, fallback_fonts)

	var hud_theme: Theme = null
	if ResourceLoader.exists(_HUD_THEME_PATH):
		hud_theme = load(_HUD_THEME_PATH)
	_add_fallbacks_to_theme(
		hud_theme, fallback_fonts)


static func _add_fallbacks_to_theme(
	theme: Theme,
	fallback_fonts: Array[Font],
) -> void:
	if theme == null:
		return

	var default_font := theme.default_font
	if default_font is FontFile:
		_add_fallbacks_to_font(
			default_font, fallback_fonts)

	# Also add to button font if different.
	if theme.has_font("font", "Button"):
		var btn_font := theme.get_font(
			"font", "Button")
		if (btn_font is FontFile
				and btn_font != default_font):
			_add_fallbacks_to_font(
				btn_font, fallback_fonts)


static func _add_fallbacks_to_font(
	font: FontFile,
	fallback_fonts: Array[Font],
) -> void:
	for fb in fallback_fonts:
		if fb not in font.fallbacks:
			font.fallbacks.append(fb)
