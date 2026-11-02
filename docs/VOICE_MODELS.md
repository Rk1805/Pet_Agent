# Character voice models (research, not implemented)

Collected from Hugging Face on 2 Nov 2026 for giving each pet its own voice. Nothing here is wired
into the app yet.

## How these would be used

Almost every character voice on Hugging Face is an **RVC** (Retrieval-based Voice Conversion)
model: a ~55 MB `.pth` file plus an `.index` file, usually shipped together in a `.zip`. RVC
doesn't read text. It **converts one voice into another**, so the pipeline would be:

```
pet's reply (text) → normal text-to-speech (e.g. Apple voice or Kokoro) → RVC model → character's voice
```

RVC keeps the words and pronunciation of the input speech and swaps the timbre. So a model trained
on the Japanese or Brazilian-Portuguese dub can still speak English replies: you get the
character's voice quality with the TTS voice's English. An English-source model is still a bit
more natural.

For characters with no trained model, **zero-shot voice cloning** can copy a voice from a few
seconds of reference audio. The myinstants clips already in `Sounds/` could serve as that
reference (see the last section).

None of the RVC repos below have a model card. Language and source are inferred from the repo and
file names and are marked as such. File size is a rough quality hint: RVC weights are always about
55 MB, and bigger zips usually carry a bigger index, meaning more training audio.

## Picks per character

**Bold** = my pick. "JP" = original Japanese voice, "PT-BR" = Brazilian Portuguese dub,
"LAT" = Latin-American Spanish dub, "EN" = English.

### Naruto pack

| Character | Models | Notes |
| --- | --- | --- |
| Naruto | **[binant/NarutoUzumaki](https://huggingface.co/binant/NarutoUzumaki)** (pth + 103 MB index) · [Narufan/Naruto_Uzumaki_315_Epochs](https://huggingface.co/Narufan/Naruto_Uzumaki_315_Epochs) (59 MB zip) · [Narufan202/Naruto_Uzumaki_By_Narufan202_225_Epochs](https://huggingface.co/Narufan202/Naruto_Uzumaki_By_Narufan202_225_Epochs) | Language unknown. binant has the largest index and loose files (no zip to unpack) |
| Sasuke | **[Clarkseokjin/NoriakiSugiyamaRVC → SasukeUchiha.zip](https://huggingface.co/Clarkseokjin/NoriakiSugiyamaRVC/blob/main/SasukeUchiha.zip)** (491 MB, JP) · [binant/sasuke_male](https://huggingface.co/binant/sasuke_male) · [geekdom-tr/Uchiha-Sasuke](https://huggingface.co/geekdom-tr/Uchiha-Sasuke) (113 MB) · [Tsuinzues/uchihasasuke](https://huggingface.co/Tsuinzues/uchihasasuke) (PT-BR?) · [TexX/Sasuke_Uchiha](https://huggingface.co/TexX/Sasuke_Uchiha) · [ShyguyTy/Sasuke](https://huggingface.co/ShyguyTy/Sasuke) · [f304/Sasuke](https://huggingface.co/f304/Sasuke) · [Vitin442/Sasuke](https://huggingface.co/Vitin442/Sasuke) | The JP pick is from a repo built around his Japanese voice actor, Noriaki Sugiyama (same repo has `NoriakiSugiyama400.zip`) |
| Sakura | **[geekdom-tr/Haruno-Sakura](https://huggingface.co/geekdom-tr/Haruno-Sakura)** (56 MB) | Only one found; language unknown |
| Kakashi | **[AIMANJP/KazuhikoInoue → Kakashi.zip](https://huggingface.co/AIMANJP/KazuhikoInoue/blob/main/Kakashi.zip)** (JP) · [Paulobad12/Kakashi](https://huggingface.co/Paulobad12/Kakashi) (RVC v2, loose files) · [Tsuinzues/kakashi](https://huggingface.co/Tsuinzues/kakashi) (PT-BR?) · [Alkinda/Kakashi_Naruto_Latino](https://huggingface.co/Alkinda/Kakashi_Naruto_Latino) (LAT) · [retrord1997/KakashiHatakelatino](https://huggingface.co/retrord1997/KakashiHatakelatino) (LAT) | AIMANJP is a Japanese anime collection named after Kakashi's JP voice actor |
| Hinata | **[lucasgamer469/hinata_rvc](https://huggingface.co/lucasgamer469/hinata_rvc)** (200 epochs, loose files) · [Tsuinzues/hinatahyuga](https://huggingface.co/Tsuinzues/hinatahyuga) (PT-BR?) | |
| Tsunade | **[Tsuinzues/tsunade](https://huggingface.co/Tsuinzues/tsunade)** (PT-BR?) | Only one found |
| Itachi | **[binant/itachi_male](https://huggingface.co/binant/itachi_male)** · [dfgdfs/Itachi](https://huggingface.co/dfgdfs/Itachi) · [jicocoli/ITACHI](https://huggingface.co/jicocoli/ITACHI) · [ngkk/itachiVF500EpochsRVC1](https://huggingface.co/ngkk/itachiVF500EpochsRVC1) (French dub, 500 epochs) · [naveenkumar1126/Itachiuchihatamil](https://huggingface.co/naveenkumar1126/Itachiuchihatamil) (Tamil dub) | |
| Rock Lee | **[Tsuinzues/rocklee](https://huggingface.co/Tsuinzues/rocklee)** (PT-BR?) | Only one found |
| Might Guy | **[Tsuinzues/guysensei](https://huggingface.co/Tsuinzues/guysensei)** (PT-BR?) | Only one found |
| Jiraiya | Maybe [AIMANJP/KazuhikoInoue → Ero.zip](https://huggingface.co/AIMANJP/KazuhikoInoue/blob/main/Ero.zip) | **Unverified guess**: "Ero" could be *Ero-sennin* (Naruto's nickname for Jiraiya) in this JP Naruto-heavy collection. Listen before relying on it |
| Pain | none found | [marcos55/nagato05](https://huggingface.co/marcos55/nagato05) exists, but it's unclear which "Nagato" it is (the name also matches Azur Lane / KanColle / Haruhi characters) |
| Shikamaru, Ino, Choji | none found | Use zero-shot cloning (below) |

Bonus from the same JP collection: Kisame, Orochimaru and Zabuza models in
[AIMANJP/KazuhikoInoue](https://huggingface.co/AIMANJP/KazuhikoInoue/tree/main), and
[HinaBl/Akatsuki](https://huggingface.co/HinaBl/Akatsuki) (unclear which member).

### Spider-Man pack

| Character | Models | Notes |
| --- | --- | --- |
| Spider-Man | **[TJKAI/TomHolland](https://huggingface.co/TJKAI/TomHolland)** (EN, MCU) · [Goldyhghoul/tomholland](https://huggingface.co/Goldyhghoul/tomholland) · [foutour/Spider-Man_PS4](https://huggingface.co/foutour/Spider-Man_PS4) (EN, Insomniac game, Yuri Lowenthal) · [EthanRhys/Spider-Man](https://huggingface.co/EthanRhys/Spider-Man) · [Hazza1/Spider-Man](https://huggingface.co/Hazza1/Spider-Man) (415 MB) · [Goldeath/Spiderman](https://huggingface.co/Goldeath/Spiderman) · [Tsuinzues/homemaranhatomholland](https://huggingface.co/Tsuinzues/homemaranhatomholland) (PT-BR dub of Holland) | No Tobey Maguire or Andrew Garfield models found |
| Miles Morales | **[ClementineRVC/MilesMoralesPS4](https://huggingface.co/ClementineRVC/MilesMoralesPS4)** (EN, Insomniac game) · [Tsuinzues/miles-morales](https://huggingface.co/Tsuinzues/miles-morales) (PT-BR?) | No Shameik Moore (film) model found |
| Spider-Gwen | **[trulyrings/haileesteinfeld](https://huggingface.co/trulyrings/haileesteinfeld)** (EN, Hailee Steinfeld, *Across the Spider-Verse*) · [Coolwowsocoolwow/Spider-Gwen](https://huggingface.co/Coolwowsocoolwow/Spider-Gwen) · [TJKAI/GwenStacy](https://huggingface.co/TJKAI/GwenStacy) · [N3gat1v3Z3r0/GwenStacy](https://huggingface.co/N3gat1v3Z3r0/GwenStacy) · [Tsuinzues/gwenaranhaverso](https://huggingface.co/Tsuinzues/gwenaranhaverso) (PT-BR Spider-Verse dub) | The TJKAI / N3gat1v3Z3r0 "Gwen Stacy" could be Emma Stone's movie Gwen: unverified |
| Doctor Octopus | **[Hazza1/OttoOctavius](https://huggingface.co/Hazza1/OttoOctavius)** (179 MB) · [FanFierik/Octavius](https://huggingface.co/FanFierik/Octavius) | Probably Alfred Molina, but unverified |
| Green Goblin | **[JoonBoy/Willem-Dafoe-Green-Goblin-v1](https://huggingface.co/JoonBoy/Willem-Dafoe-Green-Goblin-v1)** (EN, Willem Dafoe, 134 MB) · [Hazza1/GreenGoblin](https://huggingface.co/Hazza1/GreenGoblin) | |
| Venom | **[YourLocalWorm/Venom_spiderman2 → VenomInsomniacV1_515e_28840s.zip](https://huggingface.co/YourLocalWorm/Venom_spiderman2/blob/main/VenomInsomniacV1_515e_28840s.zip)** (EN, Insomniac *Spider-Man 2* Venom, 515 epochs) | ⚠️ That repo also contains a 1.3 GB pirated *Venom: Let There Be Carnage* movie rip. Only download the `VenomInsomniac*.zip` files. No Tom Hardy (film) model found |

## For characters with no model: zero-shot cloning

These can imitate a voice from roughly 5–15 s of reference audio, such as the myinstants clips
in `Sounds/`. Quality is below a trained RVC model, but it covers Shikamaru, Ino, Choji, Pain and
the rest. They do text-to-speech themselves, so no separate TTS step is needed.

| Model | Size | Notes |
| --- | --- | --- |
| [lj1995/GPT-SoVITS](https://huggingface.co/lj1995/GPT-SoVITS) | ~0.5 GB | Strong few-shot cloning, Japanese/English/Chinese; can also be fine-tuned on a minute of audio |
| [SWivid/F5-TTS](https://huggingface.co/SWivid/F5-TTS) | ~1.3 GB | Very natural zero-shot cloning (English/Chinese) |
| [coqui/XTTS-v2](https://huggingface.co/coqui/XTTS-v2) | ~2 GB | Multilingual including **Hindi**; non-commercial licence |
| [myshell-ai/OpenVoiceV2](https://huggingface.co/myshell-ai/OpenVoiceV2) | small | Copies tone colour onto a base TTS voice; MIT licence |

## Supporting models

| Model | What for |
| --- | --- |
| [lj1995/VoiceConversionWebUI](https://huggingface.co/lj1995/VoiceConversionWebUI) | The RVC project's base files: `hubert_base.pt` (190 MB) and `rmvpe.pt` (181 MB), needed to run any RVC model above |
| [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) | Small, good-quality English TTS (327 MB) to feed into RVC instead of Apple's voices |

## Things to weigh before implementing

- **Weight:** RVC and the cloning models run on Python + PyTorch (~2 GB installed) and use
  0.5–2 GB of RAM while speaking, on Apple Silicon via Metal (MPS). That's far from the app's
  25 MB, so it would have to be an optional download that loads only while a pet is talking. A
  middle ground is to pre-render a fixed set of lines (mission acknowledgements, "Done!") per
  character once and play those as audio files: no model at runtime at all.
- **Rights:** these are clones of real people's voices (voice actors and film actors), trained on
  copyrighted audio. The repos mostly carry an OpenRAIL licence, but that doesn't grant rights to
  the voices themselves. Fine for personal experiments on your own Mac; don't ship them in the app
  or the repo.
- **Unverified models:** none of these come with samples or descriptions. Each one needs a quick
  listen before it's trusted for a character.
