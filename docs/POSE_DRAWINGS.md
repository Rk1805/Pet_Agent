# Pose drawings for real animation

Each character in `art/` is one front-facing drawing, so on its own it can only be
moved around, not animated. To get anime-style motion (side-view walking,
hands moving to the mouth when eating, curling up to sleep, proper jutsu), the
pets need drawings of each pose. Drop them in and rebuild: any animation with
a drawing uses it, the rest keep the current fallback.

## How it works

1. Generate the drawings with your image tool. Attach the character's cut-out
   (`art/<id>.png`) or the full sheet (`art/source/character_sheet.png`) as the
   reference, so outfit and style stay the same.
2. Save each one as `art/<id>/<animation>.png`, for example
   `art/naruto_shippuden/walk.png`.
3. Run `python3 tools/sprites/build.py <id>` and open `preview/index.html`. The build
   prints which animations came from drawings.

Rules for every drawing:

- **Layout:** one horizontal row of poses in playing order, evenly spaced, not touching.
- **Character:** the whole body in every pose, at the same size, on a plain white background.
- **Facing:** sideways, toward the **right**, for walk, drag and jutsu. The app mirrors it
  when the pet walks left.
- **Sizing:** the background is removed automatically, and every pose is scaled to the pet's height.
- **Sprite-sheet grids** (e.g. from Higgsfield AutoSprite) work too. Add a
  `frames.json` with `{"walk": {"grid": [5, 5]}}`.

Optional tuning in `art/<id>/frames.json`: `hold` is how long each pose stays on
screen (in tenths of a second), `frames` is the number of poses in the row, and
`height` is the pose height relative to standing (sleep defaults to 0.38).

## Prompt template

> Using the attached character as the exact reference (same face, hair, outfit,
> colours and anime art style), draw **CHARACTER** as an animation sprite strip:
> **N poses in a single horizontal row**, evenly spaced and not overlapping. Full body in
> every pose, same size, **facing right**, plain white background, no text, no
> shadows on the ground. The poses show: **ACTION**.

Common actions:

- **walk** (8 poses): a side-view walk cycle, a natural anime walk, arms swinging
  opposite to the legs. The last pose loops back to the first.
- **idle** (4 poses): standing relaxed, breathing, one pose blinking.
- **drag** (4 poses): being held up by the back of the collar, legs dangling and
  kicking, surprised face.
- **sleep** (4 poses): lying on the ground on one side, curled up asleep, chest
  rising and falling.

Idles (6 poses):

- **ramen**: eats a bowl of Ichiraku ramen: lifts noodles with chopsticks to his mouth, slurps, chews happily
- **chips**: eats from a bag of potato chips, hand to mouth, crunching
- **tomato**: takes bites from a red tomato
- **dango**: eats dango from a stick, one ball at a time
- **sake**: drinks sake from a small cup, cheeks getting red
- **read**: reads an orange Icha Icha book, giggling behind his mask
- **research**: scribbles in a notebook, grinning
- **flower**: smells a flower and smiles
- **cinnamon_roll**: nibbles a cinnamon roll shyly
- **shogi**: thinks with a hand on his chin holding a shogi piece, then smirks

Jutsu (6-8 poses, in order from start to finish):

- **shadow_clone**: forms the cross-shaped clone hand sign, then two identical clones pop out of white smoke beside him
- **rasengan**: cups a swirling blue chakra sphere in his right palm, it grows, then he lunges forward and thrusts it
- **rasenshuriken**: raises his right arm overhead holding a Rasengan with four white spinning shuriken blades, then throws it forward
- **sage_mode**: stands with palms pressed together meditating, orange pigment appears around his eyes, then opens toad-like eyes
- **chidori**: crouches holding his right wrist with his left hand while blue-white lightning crackles in his palm, then dashes forward with the arm extended
- **fireball**: forms the tiger hand sign at his mouth and breathes out a huge orange fireball
- **amaterasu**: stares forward with the Mangekyo Sharingan, a drop of blood runs from one eye, black flames burst ahead of him
- **susanoo**: stands calm with the Mangekyo Sharingan as a giant translucent warrior skeleton of chakra forms around him
- **inner_sakura**: clenches a fist and pumps it up angrily shouting, fiery determined face
- **substitution**: makes a hand sign, vanishes in a puff of smoke and a wooden log appears in her place, then she reappears
- **cherry_blossom_impact**: leaps up with a glowing chakra fist raised, then punches the ground, cracking it with rocks flying
- **healing**: holds both palms forward with soft green healing chakra glowing between her hands
- **shadow_possession**: kneels slightly forming the rat hand sign, his shadow stretches forward along the ground
- **shadow_neck_bind**: forms the rat hand sign, shadow hands rise from the ground ahead of him and grab
- **shadow_stitching**: forms the rat hand sign, sharp black shadow needles shoot up from the ground ahead of him
- **cloud_watch**: lies on his back on the grass with hands behind his head, lazily watching clouds
- **mind_transfer**: forms the diamond-shaped hand sign pointing forward, then her body slumps as her spirit leaves
- **flower_storm**: spreads her arms as colourful flower petals swirl around her
- **expansion**: makes a hand sign and his body inflates to giant size, then shrinks back
- **human_bullet_tank**: expands into a huge ball, tucks in head and limbs, and rolls forward spinning
- **butterfly_mode**: bursts into chakra, glowing pink butterfly wings unfold from his back
- **partial_expansion**: throws a punch and his fist grows enormous
- **lightning_blade**: pushes up his forehead protector to reveal the Sharingan, lightning gathers in his right hand, he charges forward
- **kamui**: focuses his Mangekyo Sharingan eye, a swirling purple vortex appears in the air ahead of him
- **toad_summoning**: bites his thumb and slams his palm on the ground, a giant orange toad with a pipe appears in smoke
- **byakugan**: forms a hand sign, veins bulge around her eyes as the Byakugan activates
- **gentle_fist**: takes the Hyuga stance and strikes forward with open palms glowing blue
- **eight_trigrams**: stands in a trigram circle and strikes rapidly with both palms, chakra bursts at each hit
- **twin_lion_fists**: both fists are engulfed in blue chakra shaped like lion heads, then she lunges forward
- **ground_smash**: raises a fist with a confident smirk and smashes the ground, it cracks and shatters
- **katsuyu**: bites her thumb and slams the ground, a giant white-and-blue slug appears in smoke
- **crow_clone**: stands still, then his body bursts into a flock of black crows that fly away and return to form him again

## Files per character

| Character | Folder | Drawings |
| --- | --- | --- |
| Naruto Uzumaki (classic) | `art/naruto/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `ramen.png`, `shadow_clone.png`, `rasengan.png` |
| Naruto Uzumaki (shippuden) | `art/naruto_shippuden/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `ramen.png`, `rasenshuriken.png`, `sage_mode.png`, `shadow_clone.png` |
| Sasuke Uchiha (classic) | `art/sasuke/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `tomato.png`, `chidori.png`, `fireball.png` |
| Sasuke Uchiha (shippuden) | `art/sasuke_shippuden/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `tomato.png`, `chidori.png`, `amaterasu.png`, `susanoo.png` |
| Sakura Haruno (classic) | `art/sakura/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `dango.png`, `inner_sakura.png`, `substitution.png` |
| Sakura Haruno (shippuden) | `art/sakura_shippuden/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `dango.png`, `cherry_blossom_impact.png`, `healing.png` |
| Shikamaru Nara (classic) | `art/shikamaru/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `shogi.png`, `shadow_possession.png`, `shadow_neck_bind.png`, `cloud_watch.png` |
| Shikamaru Nara (shippuden) | `art/shikamaru_shippuden/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `shogi.png`, `shadow_possession.png`, `shadow_stitching.png` |
| Ino Yamanaka (classic) | `art/ino/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `flower.png`, `mind_transfer.png`, `flower_storm.png` |
| Ino Yamanaka (shippuden) | `art/ino_shippuden/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `flower.png`, `mind_transfer.png`, `healing.png` |
| Choji Akimichi (classic) | `art/choji/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `chips.png`, `expansion.png`, `human_bullet_tank.png` |
| Choji Akimichi (shippuden) | `art/choji_shippuden/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `chips.png`, `butterfly_mode.png`, `partial_expansion.png` |
| Hinata Hyuga (classic) | `art/hinata/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `cinnamon_roll.png`, `byakugan.png`, `gentle_fist.png` |
| Hinata Hyuga (shippuden) | `art/hinata_shippuden/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `cinnamon_roll.png`, `byakugan.png`, `eight_trigrams.png`, `twin_lion_fists.png` |
| Kakashi Hatake (jonin) | `art/kakashi/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `read.png`, `lightning_blade.png`, `kamui.png` |
| Jiraiya (sannin) | `art/jiraiya/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `research.png`, `toad_summoning.png`, `rasengan.png` |
| Tsunade (sannin) | `art/tsunade/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `sake.png`, `ground_smash.png`, `healing.png`, `katsuyu.png` |
| Itachi Uchiha (akatsuki) | `art/itachi/` | `walk.png`, `idle.png`, `drag.png`, `sleep.png`, `dango.png`, `crow_clone.png`, `amaterasu.png`, `susanoo.png` |
