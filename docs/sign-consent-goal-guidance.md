### Scope

Update the Sign Consent screen to make the signature action more clearly tappable and visually distinct from the standard text fields.

After the UI changes, fix the post-enrollment navigation so tapping "Sign and Enroll" takes the user to the new page that replaced the old study details page. The destination page says "Welcome. Thanks for choosing to participate in this study!" and has a "Begin Orientation" button.

### Preserve Existing Screen Structure

Starting from the original screen, keep the overall page structure the same. The following elements should remain in place:

- Status bar
- Back button
- Centered "Sign Consent" navigation title
- "Step 2 of 2" label
- Blue progress bar
- Main "Sign Consent" heading
- Explanatory paragraph
- First name field
- Last name field
- Signed date row
- Secure copy row
- Disabled "Sign and Enroll" button
- "I do not agree" link
- Development Supabase badge

### Consent Acknowledgment Card

In the original UI, the text "I am 18 or older, understand participation is voluntary, and agree to participate." appears as a standalone bordered card above the name fields.

Keep this acknowledgment as a bordered card, but make it feel more like an informational consent confirmation rather than a checkbox or form input.

Requirements:

- Keep the acknowledgment in a full-width card.
- Use rounded corners and a light gray border.
- Add a simple blue person/user icon on the left side of the card.
- Place the acknowledgment text to the right of the icon.
- Do not include a checkbox.

### Signature Area

The current signature section looks too much like another text input because the "Draw signature" control is a plain white outlined rectangle with the same visual treatment as the name fields.

Replace it with a more obviously tappable signature button.

Requirements:

- Keep the "Signature" label above the button.
- Make the signature button a full-width rounded rectangle.
- Make the button visually distinct from text fields.
- Use a very light blue background or blue-tinted fill.
- Use a clear blue border.
- Use blue content inside the button.
- Include a blue pen/signature icon on the left.
- Include a thin vertical divider line next to the icon.
- To the right of the divider, display one line of button text: "Tap to draw your signature."
- Do not include secondary explanatory text inside the button.
- Make the button text bold or semibold and blue so it clearly reads as an action.

### Informational Rows

After the signature button, keep the informational rows from the original screen:

- Calendar icon row reading "Signed today, Jun 28, 2026"
- Lock icon row reading "A signed consent copy will be saved securely."

These rows should remain below the signature button with similar spacing. They may shift slightly downward as needed to accommodate the redesigned button.

### Visual Direction

Preserve the original clean iOS-style layout, spacing, typography, and blue accent color.

The two key interaction changes are:

- The consent acknowledgment is presented without a checkbox.
- The signature control becomes an unmistakable tappable button with blue styling, a pen icon, divider, and the text "Tap to draw your signature."

### Navigation Behavior

After tapping "Sign and Enroll", route the user to the new page that replaced the old study details page.

The destination page should be identifiable by:

- Heading or text: "Welcome. Thanks for choosing to participate in this study!"
- Button: "Begin Orientation"

Do not route back to the old study details page.

### Verification Criteria

The goal is complete when:

- The Sign Consent screen still contains the preserved structural elements listed above.
- The acknowledgment card has no checkbox and includes a blue user icon with the acknowledgment text.
- The signature control is a full-width blue-styled tappable button with a pen/signature icon, divider, and the exact text "Tap to draw your signature."
- The signed date and secure copy rows remain below the signature button.
- The "Sign and Enroll" action navigates to the welcome/orientation page, not the old study details page.
- Relevant checks or simulator verification have been run when practical, using the `TinniTrack Development` scheme.
