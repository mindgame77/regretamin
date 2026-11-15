-- Undo the firm_directory_page hidden-firm filter. Leaves the rest of the function as it is.
do $mig$
declare
  d text;
  sig text := 'public.firm_directory_page(int,int,text,boolean,text[],text[],text[],text[],text[],text[],text[])';
  extra text := ' and not coalesce(f.demand_hidden, false)';
begin
  if to_regprocedure(sig) is null then
    return;
  end if;
  select pg_get_functiondef(sig::regprocedure) into d;
  if position(extra in d) = 0 then
    return;
  end if;
  execute replace(d, extra, '');
end
$mig$;
