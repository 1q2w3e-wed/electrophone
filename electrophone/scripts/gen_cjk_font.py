from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = Path(r"C:\Windows\Fonts\simhei.ttf")
OUT_VHDL = ROOT / "src" / "cjk_font_rom.vhd"
OUT_PREVIEW = ROOT / "sim" / "output" / "cjk_font_preview.png"

CHARS = [
    ("CJK_DIAN", "电"),
    ("CJK_ZI", "子"),
    ("CJK_QIN", "琴"),
    ("CJK_CAN", "参"),
    ("CJK_SHU", "数"),
    ("CJK_TAI", "台"),
    ("CJK_DANG", "当"),
    ("CJK_QIAN", "前"),
    ("CJK_YIN", "音"),
    ("CJK_SE", "色"),
    ("CJK_LIANG", "量"),
    ("CJK_QI", "起"),
    ("CJK_SHUAI", "衰"),
    ("CJK_JIAN", "减"),
    ("CJK_CHI", "持"),
    ("CJK_XU", "续"),
    ("CJK_SHI", "释"),
    ("CJK_BO", "波"),
    ("CJK_BO2", "拨"),
    ("CJK_XING", "形"),
    ("CJK_YU", "预"),
    ("CJK_LAN", "览"),
    ("CJK_BAO", "包"),
    ("CJK_LUO", "络"),
    ("CJK_ZHENG", "正"),
    ("CJK_XIAN", "弦"),
    ("CJK_FANG", "方"),
    ("CJK_JU", "锯"),
    ("CJK_CHI2", "齿"),
    ("CJK_SAN", "三"),
    ("CJK_JIAO", "角"),
    ("CJK_YI", "已"),
    ("CJK_HUI", "恢"),
    ("CJK_FU", "复"),
    ("CJK_MO", "默"),
    ("CJK_REN", "认"),
    ("CJK_PIN", "频"),
    ("CJK_BA", "八"),
    ("CJK_LU", "路"),
    ("CJK_YA", "压"),
    ("CJK_LI", "力"),
    ("CJK_WAN", "弯"),
    ("CJK_ROU", "揉"),
    ("CJK_HUA", "滑"),
    ("CJK_TA", "踏"),
    ("CJK_BAN", "板"),
    ("CJK_PU", "谱"),
    ("CJK_LI2", "李"),
    ("CJK_SA", "萨"),
    ("CJK_RU", "如"),
    ("CJK_XIAO", "效"),
    ("CJK_GUO", "果"),
    ("CJK_YUAN", "原"),
    ("CJK_SHENG", "声"),
    ("CJK_YAN", "延"),
    ("CJK_CHI3", "迟"),
    ("CJK_HE", "合"),
    ("CJK_CHANG", "唱"),
    ("CJK_HUN", "混"),
    ("CJK_XIANG", "响"),
]


def glyph_rows(ch: str, font: ImageFont.FreeTypeFont) -> list[int]:
    image = Image.new("L", (16, 16), 0)
    draw = ImageDraw.Draw(image)
    draw.text((8, 8), ch, font=font, fill=255, anchor="mm")
    rows = []
    for y in range(16):
        value = 0
        for x in range(16):
            if image.getpixel((x, y)) >= 96:
                value |= 1 << (15 - x)
        rows.append(value)
    return rows


def make_preview(glyphs: list[list[int]]) -> None:
    scale = 4
    cols = 7
    cell_w, cell_h = 22, 25
    rows = (len(glyphs) + cols - 1) // cols
    image = Image.new("RGB", (cols * cell_w, rows * cell_h), (8, 14, 24))
    draw = ImageDraw.Draw(image)
    label_font = ImageFont.load_default()
    for index, rows_bits in enumerate(glyphs):
        ox = (index % cols) * cell_w + 3
        oy = (index // cols) * cell_h + 2
        for y, bits in enumerate(rows_bits):
            for x in range(16):
                if bits & (1 << (15 - x)):
                    draw.rectangle(
                        (ox + x, oy + y, ox + x, oy + y),
                        fill=(80, 230, 220),
                    )
        draw.text((ox + 3, oy + 17), str(index), fill=(255, 255, 255), font=label_font)
    OUT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    image.resize(
        (image.width * scale, image.height * scale),
        Image.Resampling.NEAREST,
    ).save(OUT_PREVIEW)


def make_vhdl(glyphs: list[list[int]]) -> None:
    enum_names = ["CJK_SPACE", *[name for name, _ in CHARS]]
    enum_lines = [
        f"        {name}{',' if index < len(enum_names) - 1 else ''}"
        for index, name in enumerate(enum_names)
    ]
    glyph_lines = []
    entries = [("CJK_SPACE", None), *[(name, rows) for (name, _), rows in zip(CHARS, glyphs)]]
    for index, (name, rows) in enumerate(entries):
        if rows is None:
            suffix = "," if index < len(entries) - 1 else ""
            glyph_lines.append(f'        {name} => (others => x"0000"){suffix}')
        else:
            values = ", ".join(f'x"{value:04X}"' for value in rows)
            suffix = "," if index < len(entries) - 1 else ""
            glyph_lines.append(f"        {name} => ({values}){suffix}")

    content = f"""library ieee;
use ieee.std_logic_1164.all;

-- Generated 16x16 Chinese glyph subset. Run scripts/gen_cjk_font.py to rebuild.
package cjk_font_rom is
    type cjk_char_t is (
{chr(10).join(enum_lines)}
    );
    type cjk_string_t is array (natural range <>) of cjk_char_t;
    type glyph_rows_t is array (0 to 15) of std_logic_vector(15 downto 0);
    type glyph_table_t is array (cjk_char_t) of glyph_rows_t;

    constant CJK_GLYPHS : glyph_table_t := (
{chr(10).join(glyph_lines)}
    );

    function cjk_row(ch : cjk_char_t; row : natural) return std_logic_vector;
end package;

package body cjk_font_rom is
    function cjk_row(ch : cjk_char_t; row : natural) return std_logic_vector is
    begin
        if row > 15 then
            return x"0000";
        end if;
        return CJK_GLYPHS(ch)(row);
    end function;
end package body;
"""
    OUT_VHDL.write_text(content, encoding="utf-8")


def main() -> None:
    font = ImageFont.truetype(str(FONT_PATH), 16)
    glyphs = [glyph_rows(ch, font) for _, ch in CHARS]
    make_preview(glyphs)
    make_vhdl(glyphs)
    print(f"generated {len(glyphs)} glyphs")


if __name__ == "__main__":
    main()
