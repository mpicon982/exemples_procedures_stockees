

--création d'une procédure stockée

create or replace procedure mobilites.proc_flux_centres_territoire(p_niveau_territorial text, p_code_territoire text,
                                                                   p_schema text, p_vue_materialisee text,p_seuil_flux int default 200)

    LANGUAGE plpgsql
AS
$$
declare
    --paramètres nettoyés
    v_niveau_territorial text := lower(unaccent(p_niveau_territorial));
    v_code_terrorial     text := p_code_territoire::text;
    --millésimes
    v_millesime_geom     text;
    v_millesime_rp       text;
    --requête
    v_rqt                text;
    --id sql
    v_table_geom         text;
    v_schema_rp          text;
    v_table_rp           text;
    --champs
    v_colonne_code text;
    v_colonne_nom text;

begin

    --repérage du dernier millésime rp et implémentation de la variable
    with millesimes_rp as (select distinct right(schemaname, 4)::int millesimes
                           from pg_tables
                           where schemaname ~ '^rp\d\d\d\d$')
    select max(millesimes)::text
    into v_millesime_rp
    from millesimes_rp;
    --assignation de la variable identifiant SQL contenant le nom du schéma rp
    v_schema_rp :='rp'||v_millesime_rp;
    --idem table rp
    v_table_rp := 'fd_mobpro_' || v_millesime_rp;

    --idem pour la geom

    select max(right(tablename, 4)::int)
    into v_millesime_geom
    from pg_tables
    where schemaname = 'ref_geo'
      and tablename ~ '^refcom\d\d\d\d$';
    v_table_geom := format('%I', 'refcom' || v_millesime_geom);
--gestion des erreurs et contrôles
    --repérage du bon code territorial
    execute format($a$with niveaux_valides as(
    select
        substring(column_name,'^code_(\D+)') niveau_valide
        from information_schema.columns where table_schema='ref_geo'
                                          and table_name=%L
                                          and substring(column_name,'^code_(\D+)') is not null)
    select
        niveau_valide
        from niveaux_valides where niveau_valide=$1; $a$,v_table_geom) using v_niveau_territorial
    into v_niveau_territorial;
    if v_niveau_territorial is null
        then raise exception 'Niveau territorial invalide'
                using errcode ='invalid_parameter_value'; end if;


    if p_seuil_flux<0 then raise exception 'le seuil doit être positif'
                            using errcode='invalid_parameter_value'; end if;
    if p_seuil_flux<200 then raise warning 'Attention, il est préférable de choisir un seuil de 200 minimum pour obtenir des résultats fiables';
    end if;

    --assignation de la variable contenant le nom du champ code
    --gestion des cas aav uu et bv
    if v_niveau_territorial in ('aav','uu') then
    v_colonne_code:='code_'||v_niveau_territorial||'2020';
    v_colonne_nom:='nom_'||v_niveau_territorial||'2020';
    elseif v_niveau_territorial='bv' then
    v_colonne_code:='code_'||v_niveau_territorial||'2022';
    v_colonne_nom:='nom_'||v_niveau_territorial||'2022';
    else
    v_colonne_code:='code_'||v_niveau_territorial;
    v_colonne_nom:='nom_'||v_niveau_territorial;
    end if;

    --génération de la requête


    v_rqt := format($a$create materialized view %6$I.%7$I as(
          with flux as(
              select
                  o.%2$s code_origine,
                  o.%3$s nom_origine,
                  d.%2$s code_destination,
                  d.%3$s nom_destination,
                  case when o.%2$s=%8$L and d.%2$s=%8$L then 'internes'
                       when o.%2$s=%8$L and d.%2$s!=%8$L then 'sortant'
                       when o.%2$s!=%8$L and d.%2$s=%8$L then 'entrant'
                      end typologie,
                  sum(coalesce(ipondi::numeric,0)) nb_flux


              from %4$I.%5$I m
                       join ref_geo.%1$I o on o.code_com=m.commune
                       join ref_geo.%1$I d on d.code_com=m.dclt
              where o.%2$s=%8$L or d.%2$s=%8$L
              group by o.%2$s,o.%3$s,d.%2$s,d.%3$s
              having sum(ipondi::numeric)>=%9$s),

              --postgis calcule les centroïdes à partir des surfaces des polygones, pour calculer le centroïde d'un territoire agrégé
              --il faut donc calculer la moyenne des centroïdes pondérée par la surface (donc x1 * surface1 + ... +xn * surfacen / surface totale

              centres_communes as(
              select
            r.%2$s code_centre,
            st_centroid(st_transform(geom,2154)) centre,
            st_area(st_transform(geom,2154)) surface

              from ref_geo.%1$I r where r.%2$s in (select distinct code_origine from flux)
              or r.%2$s in (select distinct code_destination from flux)
              ),
              centres_territoires as(
              select
                code_centre,
                sum(st_x(centre)*surface)/sum(surface) x_centre,
                sum(st_y(centre)*surface)/sum(surface) y_centre
              from centres_communes
              group by code_centre

              )





          select
                      row_number() over (order by f.typologie,f.code_origine,f.code_destination) id,
                      f.code_origine,
                      f.nom_origine,
                      f.code_destination,
                      f.nom_destination,
                      f.typologie,
                      f.nb_flux,
                      case when typologie !='internes' then
                      bezier(st_makeline(st_point(o.x_centre,o.y_centre,2154),st_point(d.x_centre,d.y_centre,2154)),0.2,30) end geom

          from flux f
                   join centres_territoires o on o.code_centre=f.code_origine
                   join centres_territoires d on d.code_centre=f.code_destination
                   group by
                   o.x_centre, o.y_centre, d.x_centre,d.y_centre,
                   f.code_origine,
                      f.nom_origine,
                      f.code_destination,
                      f.nom_destination,
                      f.typologie,
                      f.nb_flux);
                   $a$,
                    v_table_geom, --%1$I
                    v_colonne_code, --%2$s
                    v_colonne_nom, --%3$s
                    v_schema_rp, --%4$I
                    v_table_rp, --%5$I
                    p_schema, --%6$I
                    p_vue_materialisee, --%7$I
                    v_code_terrorial, --%8$L
                    p_seuil_flux --%9$s
             );


--contrôle visuel de la rqt
    raise notice '%',v_rqt;

--création du schéma si besoin

execute format('create schema if not exists %I',p_schema);
--drop ancienne vue
execute format('drop materialized view if exists %I.%I',p_schema,p_vue_materialisee);

--création de la vue
execute v_rqt;
raise notice '% Vue matérialisée %.% créée camarade %',chr(9773),p_schema,p_vue_materialisee,chr(9773);
end;
$$;

