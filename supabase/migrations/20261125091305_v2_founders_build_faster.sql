-- v2_founders_build() took about 11 seconds; the slow step was checking every deal row that is not filed under a
-- round against every other round. Written as two parts, the database can match them by startup in one pass.
-- Same answer, only faster. Changes nothing but this new function (added in v2_founders_view).
do $wrapci$
declare def text; neu text;
begin
  if to_regprocedure('public.v2_founders_build()') is null then
    raise notice 'v2_founders_build not present, skipping';
    return;
  end if;
  def := pg_get_functiondef('public.v2_founders_build()'::regprocedure);
  neu := replace(def, 'where e.linked or not exists (', 'where e.linked union all select e.* from ev e where not e.linked and not exists (');
  if neu <> def then execute neu; end if;
end $wrapci$;
