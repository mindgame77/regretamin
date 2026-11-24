-- firm_directory_page_v4 was only ever called by previews of the new site; the live site calls _v5.
-- Nothing in the database refers to it (no function, view or scheduled job). Founder: remove if it breaks nothing (23 Nov).
drop function if exists public.firm_directory_page_v4(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[], text[], text, text, text);
