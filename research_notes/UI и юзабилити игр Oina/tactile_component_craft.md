# Tactile / skeuomorphic "3D toy" components: craft rules and accessibility

Research date: 2026-11-14. Scope: making buttons, chips, panels and debossed text look like one solid object in a mobile game UI, plus their accessibility pitfalls. About 16 tool calls. Some primary sources (Construct.net game-button tutorial, a Medium "3D Button Anatomy" piece) returned HTTP 403 and could not be read.

## 1. How 3D "lip" buttons are built (Duolingo, Josh Comeau pattern, casual/Supercell games) and why stacked-lip buttons read as "two shapes"

### Takeaway
The best documented build (Josh Comeau's "pushable" button, which matches the Duolingo look) has three layers: a soft blurred shadow, an "edge" (lip) the **same size and same corner radius** as the face, sitting directly behind it, and a front face lifted by translateY. The lip is a **darker shade of the same hue**, and it gets a horizontal gradient that darkens toward the left and right ends so it reads as a curved side wall, not a flat slab. Pressing moves the face **down into** the lip (the lip is covered). The lip is not a second shape drawn lower. When the lip is a separate, differently sized or differently rounded, flat-coloured rectangle, the button reads as "two rectangles".

### Cited Findings
- Comeau's structure is three spans: `.shadow`, `.edge` and `.front`. Shadow and edge are absolutely positioned and fill the button. The front is in-flow and sets the size, so **edge and front have identical bounds and radius**. Stacking follows DOM order. — [Josh W. Comeau, Building a Magical 3D Button](https://www.joshwcomeau.com/animation/3d-button/)
- Colours: edge `hsl(340 100% 32%)`, front `hsl(345 100% 47%)`. The lip keeps nearly the same hue and saturation, and its lightness drops about 15 points. The shadow is `hsl(0 0% 0% / 0.25)` with `blur(4px)`. — [Comeau](https://www.joshwcomeau.com/animation/3d-button/)
- The edge gradient fakes curved sides: `linear-gradient(to left, L16% 0%, L32% 8%, L32% 92%, L16% 100%)`. The ends are darker because the rounded corners turn away from the light. — [Comeau](https://www.joshwcomeau.com/animation/3d-button/)
- Offsets: front sits at translateY −4px at rest, −6px on hover and −2px when pressed. The shadow moves the opposite way by a shorter distance (2px at rest, 4px on hover, 1px pressed). — [Comeau](https://www.joshwcomeau.com/animation/3d-button/)
- Duolingo (third-party design-system write-ups, not official): a solid, unblurred 3–4px bottom "shadow" in a darker shade of the button's own colour (green #58cc02 face, #46a302 lip). On press the button moves down 4px and the lip closes. Blurred shadows are kept for cards and not used on CTAs. Button radius is about 12–16px and chips are fully round. Secondary buttons are white with a 2px light-grey border plus a matching grey bottom edge. — [shadcn.io Duolingo design system](https://www.shadcn.io/design/duolingo); [blakecrosley.com Duolingo guide](https://blakecrosley.com/guides/design/duolingo). Sources differ (3–4px vs 4px) and none cite Duolingo directly.
- Common CSS variants: (a) an offset box-shadow with zero blur as the bottom edge, or (b) a thick border-bottom. When pressed, remove the shadow and translate the button down so it sits flush. — [Quackit 3D pushable button](https://www.quackit.com/html/templates/buttons/3d_pushable_button.cfm); [SitePoint: build a better button](https://www.sitepoint.com/build-a-better-button-in-css3)
- Extruded rounded shapes: the side wall must be rounded at top and bottom like the face, so the lower contour "starts more inwards" at the corners instead of being a straight line. Flat, unshaded side faces make the sides look unshaded. — [Adobe Community: 3D extruded rounded square](https://community.adobe.com/t5/illustrator-discussions/3d-extruded-rounded-square/m-p/15138970)
- Radius nesting: when one rounded shape sits inside another with padding p, set outer radius = inner radius + p, or the gap looks uneven. — [Hype4: radius nesting guide](https://hype4.academy/articles/design/your-radius-nesting-guide)
- Supercell, Royal Match, Candy Crush: **no reliable public anatomy breakdown was found**. Sources only describe these UIs as high-contrast with oversized icons, bright palettes and polished animation. — [Pixune mobile game UI review 2026](https://pixune.com/blog/best-examples-mobile-game-ui-design/); [Funovus on Royal Match](https://funovus.com/blogs/royal-match-dominates-match-3-what-can-all-designers-learn); [Dream Games](https://dreamgames.com/games/royal-match)
- Clash Royale changed button colours in 2019 because two buttons looked too similar. Distinct button hues are a functional concern. — [devtrackers Clash Royale post](https://devtrackers.gg/clash-royale/p/1fb35f85-they-flipped-the-queue-button-needless-to-say-i-spent-gems-to-open-a-chest-just-wow)

### Inferences
Why a stacked-lip button reads as "two shapes", based on the findings above and standard shading logic:
1. **Mismatched geometry.** If the lip is wider, narrower or has a different corner radius than the face, two silhouettes show. Fix: the lip is the face's exact shape offset down by the depth (or face bounds plus depth in height), with the same radius.
2. **Flat lip with no wall shading.** A single flat dark colour reads as a separate sticker. Fix: darken the lip toward its left and right ends (Comeau gradient), or darken it toward the bottom.
3. **Lip hue drifts from face hue.** For example the lip is grey or black-tinted and the face is coloured. Fix: same hue, lightness about −15 points, saturation the same or slightly higher. Never a neutral grey.
4. **Visible seam or gap.** A hairline of background between face and lip, from anti-aliasing or a stroke on the face only, separates them. Fix: draw the lip so it extends up under the face (full height), and put any outline around the **combined** silhouette, not around each layer.
5. **Hard lip plus a big soft blurred drop shadow at a different offset** makes two depth cues that disagree. Fix: one tight contact shadow under the whole object, or none (Duolingo uses none on CTAs).
6. **Highlight band that spans the whole width with hard edges** reads as a third shape. Fix: an inset highlight that follows the face's radius (a top inner stroke or soft top gradient) and stays inside the face.
7. **Lip too thin (1–2px) at large sizes.** It reads as an underline, not thickness. A lip too thick reads as a stacked block. Duolingo uses about 4px on roughly 48–56px-tall buttons. A plausible rule is depth ≈ 6–10% of height, which is inferred, not sourced.
8. **Pressed state that only darkens** without moving the face keeps the illusion static. Pressing must translate the face into the lip.

### Gaps
- No primary Duolingo engineering or design blog post gives official lip values.
- No reliable source documents the button anatomy of Supercell, Royal Match or Candy Crush (outline weight, bevel, inner gloss). A frame capture or teardown would be needed. The Construct.net "professional mobile game buttons" tutorial was blocked (403).

## 2. Claymorphism and neumorphism: definitions, examples, pitfalls, fixes

### Takeaway
Neumorphism (same-colour background with paired light and dark outer shadows) fails accessibility because its boundaries have very low contrast, and it is applied to clickable and non-clickable elements alike. Claymorphism (any-colour inflated shapes with two inner shadows and one outer shadow) avoids the worst of that, but still needs real text contrast, consistent light direction, hue-tinted shadows and a large radius. Neither style should carry state through shadow alone.

### Cited Findings
- NN/g (Mar 15, 2024): neumorphism "reintroduces subtle skeuomorphic elements". Its low contrast gives elements too little visual weight, which makes it inaccessible. It is used inconsistently on clickable and non-clickable elements, so clickability is hard to judge. Ultra-flat design, by contrast, had "weak signifiers". — [NN/g, Skeuomorphism](https://www.nngroup.com/articles/skeuomorphism/)
- NN/g eyetracking: weak signifiers required more user effort. — [NN/g video: flat UI elements lack clickability clues](https://www.nngroup.com/videos/flat-ui-elements-lack-clickability-clues-and-cause-confusion/)
- Axess Lab: neumorphic elements are "barely possible to see, even if you have perfect vision". Neumorphic designs often drop icon labels, and older users avoid elements they're unsure are clickable. Its fixes: text at 4.5:1 or more, non-text UI (icons, button borders) at 3:1 or more, clearer button borders, add labels. Dark variants generally had better contrast. — [Axess Lab, Neumorphism the accessible and inclusive way](https://axesslab.com/neumorphism/)
- A vendor blog reports that a typical neumorphic edge computes to about 1.4:1, well below 3:1. This is a secondary source, so treat it as indicative. — [vp0.com, What is Soft UI](https://vp0.com/blogs/what-is-soft-ui-design.md)
- Neumorphism makes on/off toggle states hard to read, and everything looks uniformly styled, which flattens hierarchy. — [setproduct neumorphism guide](https://setproduct.com/blog/neumorphism-design-guide); [UX Planet](https://uxplanet.org/the-ground-breaking-possibilities-with-neumorphism-9ed9e64c2513)
- Claymorphism was coined by Michał Malewicz, who also named neumorphism. It works on any background colour. Recipe: outer `8px 8px 16px rgba(0,0,0,.25)`, inset dark `-8px -8px 12px rgba(0,0,0,.25)`, inset light `8px 8px 12px rgba(255,255,255,.4)`, radius about 48px. Risks: it can look childish, contrast for low-vision and colour-blind users, hierarchy disruption, and motion (respect reduced motion). Use it as an enhancement on CTAs, toggles and cards, not everywhere. — [Smashing Magazine, Claymorphism: Will It Stick Around? (2022)](https://www.smashingmagazine.com/2022/03/claymorphism-css-ui-design-trend/)
- Setproduct claymorphism guide (Jun 25, 2026, R. Kamushken):
  - Shadows are tinted with the surface's own hue (H = surface darkened about 15%), "never neutral gray".
  - Inner top-left sheen `inset 4px 4px 8px rgba(255,255,255,.5)` and inner bottom-right depth `inset -6px -6px 12px rgba(H,.30)`.
  - One light direction (top-left) for the whole screen.
  - Radius: buttons 16–20px, cards 24–32px, chips fully round. Below 16px "the shadow reads as flat".
  - At most 2 elevation levels, so no clay on clay on clay. At least 16px gap between clay siblings.
  - Tap targets 48×48 minimum, buttons 52–56px tall. One saturated action colour per screen.
  - Inputs and wells use inset-only shadows.
  - Pressed: scale to 0.97 and halve shadow offsets.
  - Accessibility: text 4.5:1 minimum, dark crisp text on clay ("soft look applies to shapes, not legibility"), don't rely on shadow alone for state.
  
  — [Setproduct, Claymorphism design guide](https://www.setproduct.com/blog/claymorphism-design-guide). Caveat: the guide's own sample of white on coral #FF7A6B claims 4.5:1 but calculates to about 2.5:1. Even style guides get this wrong, so verify every pair.

### Inferences
- A "toy" button in a game is closer to claymorphism or extrusion than to neumorphism. The object should differ in colour from its background, not be the same colour as it.
- Skipping the inner top highlight, or using grey shadows, is a documented cause of a "stuck flat" or "two shapes" look.

### Gaps
- No NN/g article specifically on claymorphism was found. No user-testing data on claymorphism was found.

## 3. Single-shape approaches: inner shadows, gradient-stroke bevel, specular highlight, ambient occlusion; chips, icon buttons, toggles, trays, debossed text

### Takeaway
Make the object one silhouette and do the shading inside it: a base fill with a vertical gradient, an inner top highlight, an inner bottom shade, an optional rim or outline drawn around the whole silhouette, and one contact shadow. Inset-only shading makes "wells" and trays that read as pressed-in. Debossed text is a known legibility risk, so the glyph itself must meet 4.5:1, and the emboss highlight or shadow is decoration on top.

### Cited Findings
- Claymorphism's two inset shadows (light top-left, dark bottom-right) plus one outer shadow produce volume on a single shape. — [Smashing](https://www.smashingmagazine.com/2022/03/claymorphism-css-ui-design-trend/); [Setproduct](https://www.setproduct.com/blog/claymorphism-design-guide)
- Inputs, wells and trays: inset shadow only, no outer drop. This gives a pressed-in well. — [Setproduct](https://www.setproduct.com/blog/claymorphism-design-guide)
- Chips: fully rounded (999px or capsule). — [Setproduct](https://www.setproduct.com/blog/claymorphism-design-guide); [shadcn Duolingo](https://www.shadcn.io/design/duolingo)
- Raster game-button convention (Photoshop): an inner bevel with "chisel hard", a small low-opacity white inner glow, and a separate duplicated highlight layer. — [Thoughtbot, how to make really nice buttons](https://robots.thoughtbot.com/how-to-make-really-nice-buttons) and other search-surfaced layer-style tutorials (snippet-level only)
- Light comes from the top, so shadow forms at the bottom. A highlight is a brighter area on the top side of the button. — [3D Button Anatomy, Fizday/Medium](https://medium.com/fizday/3d-button-anatomy-video-tutorial-on-how-to-create-one-54d31277d998) (search snippet; page 403)
- SwiftUI (iOS 16+): `ShapeStyle.shadow(.inner(color:radius:x:y:))` gives a true inner shadow on a single shape, for example `Circle().fill(.shadow(.inner(radius: 1, y: 1)))`. Two-tone inner shadows can be stacked. One reported caveat is that the dark inner shadow can partly cover the white one. — [Stack Overflow: inner shadow in SwiftUI](https://backiee.wasmer.app/http_Stackoverflow_com/questions/60114699/how-to-make-inner-shadow-in-swiftui); [DevTechie: Neumorphic button in iOS 16](https://medium.com/devtechie/neumorphic-button-in-ios-16-and-swiftui-75360b41866e)
- A neumorphism-in-SwiftUI accessibility write-up discusses adapting for Increase Contrast and similar settings. — [prog.world, Neomorphism using SwiftUI part 2: accessibility](https://prog.world/neomorphism-using-swiftui-part-2-what-can-be-done-with-accessibility/) (not fetched; title-level only)

### Inferences
Recommended single-object recipe for the app, which synthesises the sources above:
- **Button or toy key:**
  - One `RoundedRectangle(cornerRadius: r, style: .continuous)` silhouette covering face and lip (height h + depth).
  - Lip colour = face hue at lightness −12 to −18. Darken the lip's left and right ends (Comeau gradient).
  - Face = same shape inset at the top by `depth`, with a subtle top-to-bottom gradient (top +4–6% L).
  - An inner top highlight: a 1–1.5pt white stroke at 30–50% opacity, masked to the top half, or `.shadow(.inner(color: .white.opacity(0.5), radius: 1, y: 1))`.
  - Optional outline (1.5–2pt, darker than the lip) around the **combined** silhouette only.
  - One tight contact shadow (y 2, blur 2–4, 20–25% of a hue-tinted dark).
- **Chips and pills:** the same recipe with a capsule shape and smaller depth (2–3pt). Selected chips should change fill or hue and add a check or icon, not only depth.
- **Icon buttons:** a circular or squircle version. The icon glyph meets 3:1 against the face.
- **Toggles:** the track is a well (inset only), and the knob is a raised object. The on state also changes colour and position. Never use depth alone.
- **Trays and score panels:** inset well with a darker inner top shadow and a lighter inner bottom rim. Keep text inside the tray at 4.5:1 against the tray fill.
- **Debossed text:** the glyph colour itself must reach 4.5:1 (3:1 for large text, 18pt or 14pt bold). Then add a 1pt light offset below (deboss) or a dark offset above. Treat the offset as decoration. Same-colour-as-background "pressed" text fails, because it is neumorphism applied to text.

### Gaps
- No authoritative source covers ambient-occlusion techniques specific to UI. No source gives SwiftUI performance data comparing many layered shapes with one shape plus inner shadows (Comeau's CSS note: animate transform and filter, not box-shadow).

## 4. Pressed, disabled and selected states; motion timings

### Takeaway
Pressed: translate the face down by most or all of the lip depth almost instantly (about 2 frames, 34ms in Comeau's build), then spring back over about 250–600ms with slight overshoot. Disabled: flatten (no lip), desaturate, but keep it visible, with a label still legible. Selected: change colour or icon as well as depth, at 3:1 against the unselected look's surroundings.

### Cited Findings
- Comeau's timings:
  - Press (`:active`): 34ms, "roughly 2 frames at 60fps".
  - Hover rise: 250ms, `cubic-bezier(0.3, 0.7, 0.4, 1.5)` (overshoot gives a spring).
  - Release back to rest: 600ms, `cubic-bezier(0.3, 0.7, 0.4, 1)`.
  - Hover adds `filter: brightness(110%)`.
  - Animate `transform` and `filter` and avoid animating `box-shadow`, which is expensive.
  - Focus ring uses `outline-offset: 4px`.
  
  — [Comeau](https://www.joshwcomeau.com/animation/3d-button/)
- Duolingo-style press: the face moves down by the full lip (about 4px) so the lip disappears. — [shadcn Duolingo](https://www.shadcn.io/design/duolingo)
- Clay press: scale 0.97 and halve shadow offsets. — [Setproduct](https://www.setproduct.com/blog/claymorphism-design-guide)
- SwiftUI: use a `ButtonStyle` and read `configuration.isPressed` to drive offset, shadow and scale. Plain modifiers can't react to press. — [Fatbobman, custom ButtonStyle](https://fatbobman.com/en/posts/custom-button-style-in-swiftui); [Kodeco SwiftUI cookbook: advanced button styling](https://www.kodeco.com/books/swiftui-cookbook/v1.0/chapters/10-advanced-button-styling-in-swiftui)
- Press and float animations should respect reduced-motion preferences. — [Smashing](https://www.smashingmagazine.com/2022/03/claymorphism-css-ui-design-trend/)
- Don't rely on shadow alone to show state. — [Setproduct](https://www.setproduct.com/blog/claymorphism-design-guide); neumorphic toggles' on/off is hard to decipher — [setproduct neumorphism](https://setproduct.com/blog/neumorphism-design-guide)

### Inferences
- In SwiftUI, `isPressed` flips on touch-down, so press with `.animation(.easeOut(duration: 0.05))` or no animation, and release with `.spring(response: 0.3, dampingFraction: 0.6)`. Under Reduce Motion, keep the colour or brightness change and drop the translation.
- Disabled: remove the lip (depth 0), use a lower-saturation fill, and keep the label at least clearly visible. WCAG exempts disabled controls, but players must still read them.
- Selected chip: a filled colour plus a checkmark, or a "sunk" well with a contrasting rim. Depth is the secondary cue.

### Gaps
- No primary source gives Duolingo's or a Supercell game's exact press timings or haptic pairing. Apple HIG haptic guidance was not fetched.

## 5. Contrast numbers for soft and tactile UI

### Takeaway
Text needs 4.5:1 (3:1 for large text). The visual cues needed to identify a control and its state need 3:1 against adjacent colours (WCAG 1.4.11). For gradients, test the least-contrasting area. Soft shadows and dark borders count as part of the nearest-brightness adjacent colour, so a 1.4:1 neumorphic edge fails if the edge is the only thing that marks the button.

### Cited Findings
- SC 1.4.11 (AA): UI component visual cues needed to identify the control and its states need 3:1 or more against adjacent colours. Ratios aren't rounded, so 2.999 fails. Hover is supplemental. State colours not shown side by side are not required to meet 3:1 against each other. Text-identified controls don't need a boundary but still need a contrasting focus indicator. Disabled controls are exempt. For gradients, test the least-contrasting area. A drop shadow or dark border that doesn't interfere is treated as part of the adjacent colour closest in brightness. — [W3C, Understanding SC 1.4.11 Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)
- Text 4.5:1 and UI elements 3:1, applied to neumorphism. — [Axess Lab](https://axesslab.com/neumorphism/)
- A typical neumorphic edge is about 1.4:1. — [vp0.com](https://vp0.com/blogs/what-is-soft-ui-design.md) (secondary)

### Inferences
- For a coloured toy button on a light board, the **face fill** against the background usually provides the 3:1 boundary, so the lip does not have to. For pale pastel buttons on pale backgrounds, the lip or an outline must reach 3:1, or the label alone must identify the control.
- For debossed score text in a tray, the glyph fill against the tray fill must reach 4.5:1. Emboss offsets don't count.
- Test both light and dark mode, and iOS Increase Contrast. Under Increase Contrast, add an outline and darken text.

### Gaps
- No WCAG guidance specific to embossed or debossed text exists beyond the general text-contrast rules. WCAG 3 / APCA thresholds were not researched.
