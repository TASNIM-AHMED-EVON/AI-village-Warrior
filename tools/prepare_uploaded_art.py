from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source_sheets"


def remove_border_background(image: Image.Image, tolerance: int = 7) -> Image.Image:
    """Clear a flat screenshot backdrop only where it connects to the image edge."""
    image = image.convert("RGBA")
    pixels = image.load()
    width, height = image.size
    background = pixels[0, 0][:3]
    marked = bytearray(width * height)
    queue = deque()

    def is_background(x: int, y: int) -> bool:
        pixel = pixels[x, y]
        return max(abs(pixel[channel] - background[channel]) for channel in range(3)) <= tolerance

    def add(x: int, y: int) -> None:
        index = y * width + x
        if not marked[index] and is_background(x, y):
            marked[index] = 1
            queue.append(index)

    for x in range(width):
        add(x, 0)
        add(x, height - 1)
    for y in range(height):
        add(0, y)
        add(width - 1, y)

    while queue:
        index = queue.popleft()
        x, y = index % width, index // width
        if x:
            add(x - 1, y)
        if x + 1 < width:
            add(x + 1, y)
        if y:
            add(x, y - 1)
        if y + 1 < height:
            add(x, y + 1)

    alpha = image.getchannel("A")
    alpha_pixels = alpha.load()
    for index, value in enumerate(marked):
        if value:
            alpha_pixels[index % width, index // width] = 0
    image.putalpha(alpha)
    return image


def remove_checkerboard_background(image: Image.Image, colors: tuple[tuple[int, int, int], ...], tolerance: int = 7) -> Image.Image:
    """Clear a checkerboard preview backdrop without keying similar pixels in the sprite."""
    image = image.convert("RGBA")
    pixels = image.load()
    width, height = image.size
    marked = bytearray(width * height)
    queue = deque()

    def is_background(x: int, y: int) -> bool:
        pixel = pixels[x, y]
        return any(max(abs(pixel[channel] - color[channel]) for channel in range(3)) <= tolerance for color in colors)

    def add(x: int, y: int) -> None:
        index = y * width + x
        if not marked[index] and is_background(x, y):
            marked[index] = 1
            queue.append(index)

    for x in range(width):
        add(x, 0)
        add(x, height - 1)
    for y in range(height):
        add(0, y)
        add(width - 1, y)
    while queue:
        index = queue.popleft()
        x, y = index % width, index // width
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1), (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1)):
            if 0 <= nx < width and 0 <= ny < height:
                add(nx, ny)
    alpha = image.getchannel("A")
    alpha_pixels = alpha.load()
    for index, value in enumerate(marked):
        if value:
            alpha_pixels[index % width, index // width] = 0
    image.putalpha(alpha)
    return image


def crop(image: Image.Image, rect: tuple[int, int, int, int], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    image.crop(rect).save(output)


def main() -> None:
    assets = ROOT / "assets"
    troops = assets / "troops"
    buildings = assets / "buildings"
    terrain = assets / "terrain"

    inputs = {
        "warrior": "codex-clipboard-149730bc-d9e0-48cb-9df9-b54153ec8ed5.png",
        "archer": "codex-clipboard-a27b1dbb-d596-4af4-894f-4cdfc2f4620c.png",
        "mage": "codex-clipboard-23884bda-d5b0-470a-8868-5be677f91b1e.png",
        "tank": "codex-clipboard-77d842c9-ba3c-4d35-9261-081b1efd9edf.png",
    }
    sheets: dict[str, Image.Image] = {}
    for name, filename in inputs.items():
        cleaned = remove_border_background(Image.open(SOURCE / filename))
        sheets[name] = cleaned
        cleaned.save(troops / f"{name}_sheet.png")

    # Standalone icons are cut from the first idle frame. The full animation
    # sheets above remain the source for the idle, movement, and attack poses.
    crop(sheets["warrior"], (0, 0, 128, 140), troops / "warrior_sprite.png")
    crop(sheets["archer"], (0, 0, 128, 140), troops / "archer_sprite.png")
    crop(sheets["mage"], (0, 0, 146, 186), troops / "mage_sprite.png")
    crop(sheets["tank"], (0, 0, 176, 155), troops / "tank_sprite.png")
    archer_icon = Image.open(troops / "archer_sprite.png").convert("RGBA")
    red, green, blue, alpha = archer_icon.split()
    archer_icon = Image.merge("RGBA", (red.point(lambda value: int(value * 0.72)), green.point(lambda value: min(255, int(value * 1.08))), blue.point(lambda value: int(value * 0.62)), alpha))
    archer_icon.save(troops / "goblin_sprite.png")

    town_hall = remove_border_background(Image.open(SOURCE / "codex-clipboard-d615f8a0-a750-496f-8ef8-f2563db9b67c.png"))
    crop(town_hall, (185, 0, 845, 559), buildings / "town_hall_sprite.png")
    barracks = remove_border_background(Image.open(SOURCE / "codex-clipboard-c4df7b6b-bb5c-4b75-953b-994f90cf530e.png"))
    crop(barracks, (190, 10, 850, 435), buildings / "barracks_sprite.png")

    utility = remove_border_background(Image.open(SOURCE / "codex-clipboard-ad7abace-7402-4d4d-b560-bf70868d6cf8.png"))
    crop(utility, (0, 0, 330, 559), buildings / "archer_tower_sprite.png")
    crop(utility, (345, 0, 645, 559), buildings / "elixir_pump_sprite.png")
    crop(utility, (650, 0, 1024, 559), buildings / "gold_mine_sprite.png")

    cannon_sheet = remove_checkerboard_background(
        Image.open(SOURCE / "codex-clipboard-08ad186c-137f-4cb0-b5a8-183f3ae24ee1.png"),
        ((172, 172, 172), (217, 217, 217)),
        14,
    )
    crop(cannon_sheet, (0, 0, 140, 120), buildings / "cannon_sprite.png")
    wall_sheet = remove_checkerboard_background(
        Image.open(SOURCE / "codex-clipboard-d20bf20d-ee1b-47f1-8363-130e99a14c69.png"),
        ((90, 90, 90), (140, 140, 140)),
        14,
    )
    crop(wall_sheet, (137, 416, 255, 548), buildings / "wall_sprite.png")

    grass = remove_border_background(Image.open(SOURCE / "codex-clipboard-7e069f0b-d344-4521-a83b-bbcea59da10a.png"))
    grass.save(terrain / "grass_atlas.png")
    # Use nine nearby atlas cells so the rendered ground does not repeat as
    # one obvious stamp. The cells are inset to omit atlas guide lines.
    grass_variants = []
    for index in range(9):
        x = 29 + index * 60
        variant = grass.crop((x, 29, x + 54, 83))
        grass_variants.append(variant)
        variant.save(terrain / f"grass_tile_{index}.png")
    grass_variants[0].save(terrain / "grass_tile.png")
    tile = grass_variants[0].resize((48, 24), Image.Resampling.NEAREST)
    diamond = Image.new("L", tile.size, 0)
    ImageDraw.Draw(diamond).polygon(((0, 12), (24, 0), (47, 12), (24, 23)), fill=255)
    tile.putalpha(Image.composite(tile.getchannel("A"), Image.new("L", tile.size, 0), diamond))
    ground = Image.new("RGBA", (2880, 1440), (0, 0, 0, 0))
    for x in range(60):
        for y in range(60):
            center_x = 1440 + (x - y) * 24
            center_y = (x + y) * 12
            ground.alpha_composite(tile, (center_x - 24, center_y - 12))
    ground.save(terrain / "village_grass_map.png")


if __name__ == "__main__":
    main()
