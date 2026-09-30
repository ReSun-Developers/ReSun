# ReSun

**ReSun** is an unofficial fan remake of *Command & Conquer: Tiberian Sun*, recreated from the ground up using the [**Redot Engine**](https://github.com/Redot-Engine/redot-engine) — an open-source game engine derived from Godot.  
The project aims to faithfully re-implement the original gameplay experience of *Tiberian Sun* with improved performance, cross-platform support, and modern modding capabilities.

This remake is designed for educational, preservation, and community purposes, allowing players and modders to explore the classic *Command & Conquer* RTS systems in an open, extendable environment.  
All gameplay logic, user interface, and engine functionality are being rebuilt to replicate the behavior of the original game while offering tools for future mod development.

> **Note:** ReSun does not aim to replace or compete with EA’s products.  
> It is a free, non-commercial fan project created in accordance with EA’s modding guidelines.

---

## License

The ReSun project is an unofficial community remake of *Command & Conquer: Tiberian Sun* built on the Redot Engine.

- **Code** — The original engine code and scripts developed for this project are licensed under the [MIT License](https://opensource.org/licenses/MIT).  
- **Custom Media Assets** — All newly created art, models, textures, audio, and other media assets produced by the project team are licensed under [Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/).  
- **Original *Tiberian Sun* Assets** — Any assets derived from or including proprietary content from Electronic Arts Inc. (EA), such as graphics, audio, data, or models, remain the exclusive property of EA and are used subject to EA’s [Modding Guidelines](https://www.ea.com/games/command-and-conquer/modding-faq) (including non-commercial distribution, free of charge).

“Command & Conquer”, “Tiberian Sun”, and other related marks are registered trademarks of Electronic Arts Inc.  
This project is **not affiliated with or endorsed by EA**.  
**EA has not endorsed and does not support this product.**

---

## Links

- [Redot Engine GitHub Repository](https://github.com/Redot-Engine/redot-engine) - Documentation: https://docs.redotengine.org/
- [EA Command & Conquer Modding FAQ](https://www.ea.com/games/command-and-conquer/modding-faq)
- [Creative Commons BY-NC 4.0 License](https://creativecommons.org/licenses/by-nc/4.0/)
- [MIT License](https://opensource.org/licenses/MIT)

---

## Development

### Prerequisites

- [Redot Engine 26.2 LTS](https://github.com/Redot-Engine/redot-engine/releases)
- Python 3.x (for linting)

### Running Tests

```bash
redot --headless -s test/run_tests.gd
```

### Linting

```bash
pip install gdtoolkit
gdlint scripts/**/*.gd test/**/*.gd
gdformat --check scripts/**/*.gd test/**/*.gd
```

### CI

GitHub Actions runs lint, format check, and tests on every push and PR. See `.github/workflows/test.yml`.

