
--fonction de création de grille --> procédure plutôt que fonction car pas de return, je préfère dinstinguer ainsi

create or replace procedure public.proc_creation_grille
(p_borne_ouest numeric, p_borne_est numeric, p_borne_nord numeric, p_borne_sud numeric, p_pas bigint, p_srid int, p_schema text, p_table text)
    language plpgsql as

$$
declare
    v_rqt_drop text :=format('drop table if exists %I.%I;',p_schema,p_table);
    v_curseur_x numeric:=p_borne_ouest;
    v_curseur_y numeric:=p_borne_sud;
    v_x_min bigint;
    v_y_min bigint;
    v_x_max bigint;
    v_y_max bigint;



begin
    --gestion des erreurs
    --cas des bornes inversées
    if p_borne_ouest >=p_borne_est or p_borne_sud>=p_borne_nord or
        --cas des bornes pas assez espacées par rapport au pas
       p_pas<=0 or
       p_borne_est-p_borne_ouest<p_pas or p_borne_nord-p_borne_sud<p_pas
    then raise exception 'incohérence de vos bornes et/ou de votre pas' using errcode='invalid_parameter_value';
    end if;

    --création de la grille
    --définition de la limite ouest de la grille
    v_x_min:=round(p_borne_ouest-p_pas)::bigint;
    --définition de la limite sud
    v_y_min:=round(p_borne_sud-p_pas)::bigint;
    --calcul des valeurs du curseur

    --calculd du x max
    while v_curseur_x<p_borne_est+p_pas loop
            v_curseur_x:=v_curseur_x+p_pas; end loop;
    v_x_max:=round(v_curseur_x)::bigint;
    --calcul du y max
    while v_curseur_y<p_borne_nord+p_pas loop
            v_curseur_y:=v_curseur_y+p_pas; end loop;
    v_y_max:=round(v_curseur_y)::bigint;
    --création de la liste de valeurs et de la requête en même temps
    execute v_rqt_drop;
    execute format($a$create table %I.%I as(
    with curseur_x as(
        select x from generate_series($1,$2,$3) g(x)),
                                          curseur_y as(
                                              select y from generate_series($4,$5,$3) g(y)
                                          ),

                                          t as(
                                              select row_number() over (order by x)::text||'-x' id, x as coord, st_makeline(st_point(x,$4,$6),st_point(x,$5,$6)) geom
                                              from curseur_x
                                              union all
                                              select row_number() over (order by y)::text||'-y' id, y, st_makeline(st_point($1,y,$6),st_point($2,y,$6)) geom
                                              from curseur_y)

                                     select id, coord, geom from t);$a$,p_schema,p_table)
    using v_x_min,v_x_max,p_pas,v_y_min,v_y_max,p_srid;

    raise notice 'Requête exécutée.%Table %.% créée camarade %',chr(10),p_schema,p_table,chr(9773);

end;

$$;

comment on procedure proc_creation_grille(p_borne_ouest numeric, p_borne_est numeric, p_borne_nord numeric, p_borne_sud numeric, p_pas bigint, p_srid int, p_schema text, p_table text)
    is E'Procédure de création de grille personnalisée, à privilégier avec des systèmes de coordonnées PLANES. Ne pas en abuser pour ne pas créer des tables très lourdes.\nLa procédure ne crée pas d''index et de pk, à vous de le faire si besoin\n Paramètres :\n borne ouest , borne est, borne nord, borne sud --> nombres réels ; pas (écart entre les lignes de grilles) nb entier ; srid (nb entier) ; nom du schéma ; nom de la table';
