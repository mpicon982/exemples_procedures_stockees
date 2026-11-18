

create or replace procedure exploitations_rp.proc_5_structure_par_age_et_par_sexe_detaillee(p_millesime_rp int default 2023,
                                                                                  p_millesime_geom int default 2026)
    language plpgsql AS $$
declare
    --variables des millésimes
    v_millesime_rp       text := p_millesime_rp::text;
    v_millesime_rp_court text := right(v_millesime_rp, 2);
    v_millesime_geom     text := p_millesime_geom::text;
    v_liste_nivadmin text;
    --variable de la reqûete
    v_rqt text:='';
    --identifiants sql
    v_schema_rp text:='rp'||v_millesime_rp;
    v_table_rp text:='td_population_agesex_princ_'||v_millesime_rp;
    v_table_geom text:='refcom'||v_millesime_geom;
    --création de blocs dans la rqt
    v_ages text[];
    v_lib_ages text[];
    v_sexe text[]:=array['M','F'];
    v_lib_sexe text[]:=array['hommes','femmes'];
    v_bloc_valeurs text;
    v_bloc_valeurs2 text;

    begin
    --création des tableau avec l'âge et le libellé de l'âge dans le même ordre de tri
   execute format($a$ select
                array_agg(age order by lib_age,age),
                array_agg(replace(lib_age::text,'100','100p') order by lib_age, age)
                from
                (select distinct age, substring(age,'\d+')::int lib_age from %I.%I where age!='_T') sr $a$,v_schema_rp,v_table_rp)
                into v_ages,v_lib_ages;
    --création de la partie avec les valeurs de la requête -- utilisation de min et filter (where) pour filouter avec la structure de la donnée
    v_bloc_valeurs:=
                    string_agg(format('coalesce(min(obs_value) filter (where age=%1$L and sex=%2$L),0) as p%3$s_%4$s%5$s',
                               a.v, --age %1$L
                               s.v, -- sex %2$L
                               v_millesime_rp_court, --23 %3$s
                               s.l, --lib sex %4$s
                               a.l -- lib ages %5$s
                               ),E',\n')
                    from unnest(v_ages,v_lib_ages) with ordinality a(v,l,i)
                    cross join unnest(v_sexe, v_lib_sexe) with ordinality s(v,l,i);

    v_rqt:=
        --partie niveaux communs aux deux bases (il faut penser aux SCOT et sud lorr)
        format($a$
        create view exploitations_rp.v_5_age_et_sexe_detailles as(
        select
        na.codgeo,
        na.nivadmin,
        na.nivadmin||'-'||na.codgeo code_jointure,
        %3$s,
        'INSEE RP%4$s td pop1princ : population détaille par âge et par sexe' source


        from %1$I.%2$I p
        --filtre sur les nivadmin et territoires de mon exploitation
        join (select nivadmin, codgeo from exploitations_rp.v_nivadmin) na on na.nivadmin=lower(p.geo_object)
        and na.codgeo=p.geo
        group by na.codgeo,na.nivadmin

        union all

        $a$,
           v_schema_rp, --%1$I
           v_table_rp, --%2$I
           v_bloc_valeurs, -- %3$s
           v_millesime_rp -- %4$s
           );
        --seconde partie avec les niveaux scot et sudlor
    --création du bloc contenant le calcul des valeurs de colonnes agrégées
    v_bloc_valeurs2:=replace(v_bloc_valeurs,'min','sum');
    v_rqt:=v_rqt||format($a$
        select
        na.code,
        na.niv,
        na.niv||'-'||na.code,
        %3$s,
        'INSEE RP%4$s td pop1princ : population détaille par âge et par sexe' source
        from ref_geo.%5$I r
        join %1$I.%2$I p on p.geo = r.code_com
        cross join lateral(values('sudlor',r.code_sudlor),('scot',nullif(r.code_scot,''))) na(niv,code)
        where p.geo_object='COM' and p.age!='_T' and p.sex!='_T' and na.code is not null
        group by na.code, na.niv
        );
        $a$,
                         v_schema_rp, --%1$I
                         v_table_rp, --%2$I
                         v_bloc_valeurs2, -- %3$s
                         v_millesime_rp, -- %4$s
                         v_table_geom --%5$I
                );

    raise notice 'Requête créée :% %',chr(10),v_rqt; -- chr(10) pour saut de ligne

    drop view if exists exploitations_rp.v_5_age_et_sexe_detailles;

    execute v_rqt;
    raise notice '% Procédure terminée camarade %',chr(9773),chr(9773);
    end;
$$;

call exploitations_rp.proc_5_structure_par_age_et_par_sexe_detaillee();

