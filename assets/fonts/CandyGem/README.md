# Candy Gem 字体资源包

字符范围：A–Z、a–z、0–9、空格。没有中文和标点。

## Photoshop

安装 CandyGem-Color-SVG.ttf（右键 → 安装），重新启动 Photoshop，在字体菜单选择 Candy Gem Color。
这是带有 PNG 图像的 OpenType SVG 彩色字体，保留参考图的粉紫纹理、金边和高光；内部为位图，超大放大会受到原图分辨率限制。
如果软件版本或渲染器无法显示此彩色字体，可直接置入 png 文件夹的透明字符图片。

## Godot

把 godot 文件夹中的 CandyGem.fnt 和 CandyGem.png 一起复制到项目中，保持同一目录。
在 Label 的 Theme Overrides → Fonts → Font 中加载 CandyGem.fnt，字体颜色设为白色。原生字体大小为 256，建议先设置 Font Size 为 128 或 256 再调整。
Godot 4 脚本示例见 godot/example.gd。彩色位图放大不增加细节。

## 其他软件

安装 CandyGem-Mono.ttf，字体名为 Candy Gem Mono。这是从图片轮廓制作的单色 TrueType 字体，可由应用设置文字颜色，不包含金边和纹理颜色。
透明 PNG 是跨图像软件使用彩色效果的备用方式。不存在能保证在任何软件中都保留彩色效果的单一字体格式。

## 来源和补制

数字取自 ziti.png，大写取自 zitiE1.png，小写取自本地高清 zitie.png，并与用户最后提供的小写截图核对。
小写图第一行第三个字符实际是 x，缺少 c。因此 c 是用大写 C 缩放补制的近似字形；x 使用小写图最后一行的原始 x。其余字符均从参考图提取。
已去除背景，统一字高、基线及基本字距，没有做逐字对的精细 kerning。字形轮廓来自栅格追踪。

## 检查记录

两份 TTF 均重新读取并检查了字符映射；单色版的 62 个字形均经 Pillow/FreeType 栅格化检查。已检查透明底排版预览。
没有在 Photoshop 或 Godot 应用中进行实机验证；彩色字体的显示取决于宿主软件的 OpenType SVG 支持。
preview.png 为 PNG 字符合成预览，不是 Photoshop 实机截图。
build_fonts.py 为可重复生成脚本，需要 pillow、numpy、opencv-python-headless、fonttools。

参考文档：
- https://helpx.adobe.com/photoshop/desktop/text-typography/characters-glyphs/work-with-opentype-svg-fonts.html
- https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html

字体包由用户提供图像转换而来，不附加第三方素材授权；原图权利归原权利人。
