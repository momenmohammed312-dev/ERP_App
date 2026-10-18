# FEAT-005: Create a recipe inline from the manufacturing order dialog

- Status: resolved
- Priority: medium
- Area: Manufacturing (BOM + MO form)
- Commit: 8154ad3

## User story
While entering a fixture order the operator may realize no recipe exists for
this job. Going to the recipes screen loses form context (customer, receipt,
pricing). They want to create the recipe inside the MO dialog hope and come
back to the same form.

## Decision (approved)
- Add a `new recipe` ghost button next to the recipe dropdown inside the
  MO dialog, enabled while the form is editable.
- The inline dialog reuses BomFormDialog (single source of recipe editing).
  After successful creation the MO dialog refreshes the recipe list,
  recomputes receipt compatibility, selects the new recipe and pulls its
  lines for the ownership split preview; if the recipe does not match the
  receipt lines the show-all checkbox is switched on instead of hiding it.

## Implementation
- lib/ui/manufacturing/widgets/bom_form_dialog.dart: pop returns the created
  BOM id on create, true on update (backward compatible for the recipes list
  which now treats any non-null result as success).
- lib/ui/manufacturing/bom_list_screen.dart: accepts id-or-bool results.
- lib/ui/manufacturing/widgets/mo_form_dialog.dart: `_createRecipeInline`
  (loadBoms + re-pick receipt state select + BOM lines refresh) and the
  ghost button.

## Verification
- flutter analyze (3 files): 0 errors, 0 warnings.
- flutter test manufacturing set (7 files): 45 tests, all passed.