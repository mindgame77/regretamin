-- Removes the paged investors directory function.
-- Does not change or drop public.firm_directory().

drop function if exists public.firm_directory_page(int, int, text, boolean, text[], text[], text[], text[], text[], text[], text[]);
