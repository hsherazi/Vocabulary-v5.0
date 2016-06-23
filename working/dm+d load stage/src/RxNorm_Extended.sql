

-- create table to store all future links from concrete vocab into RxE
-- fill it with natural primary keys
 
create table rxe_replace as
select concept_code, 'OMOP'||new_vocab2.nextval as rxe_code from concept_stage 
where concept_code not like 'OMOP%' 
and concept_code not in (select concept_code_1 from concept_relationship_stage where relationship_id in  ('Maps to', 'Has standard ing', 'Has standard brand','Has standard form' )) 
and invalid_reason is null
;
-- TODO identify and add here all the concepts we have to keep in the original vocabulary


-- insert copies of RxE
insert into concept_stage(concept_name, domain_id, vocabulary_id, concept_class_id, standard_concept, valid_start_date, valid_end_date, invalid_reason, concept_code)
select concept_name, domain_id, vocabulary_id, concept_class_id, standard_concept, valid_start_date, valid_end_date, invalid_reason,
rxe_code
from concept_stage cs JOIN rxe_replace rxer ON rxer.concept_code = cs.concept_code;

-- rewrite all the relationships to the newly created copies
create table rxe_rowid_update as
select crs.rowid as irowid, nvl(rxer1.rxe_code, crs.concept_code_1) as rxe_code_1 , nvl(rxer2.rxe_code, crs.concept_code_2)  as rxe_code_2 from concept_relationship_stage crs
LEFT JOIN rxe_replace rxer1 ON crs.concept_code_1=rxer1.concept_code
LEFT JOIN rxe_replace rxer2 ON crs.concept_code_2=rxer2.concept_code
WHERE rxer1.rowid is not null or rxer2.rowid is not null;

MERGE INTO concept_relationship_stage crs
USING   (
select * from rxe_rowid_update
) d ON (d.irowid=crs.rowid)
WHEN MATCHED THEN UPDATE
    SET crs.concept_code_1 = d.rxe_code_1, crs.concept_code_2 = d.rxe_code_2;

drop table rxe_rowid_update;

-- substitute vocabulary id
update concept_stage SET vocabulary_id = 'RxNorm Extension' WHERE vocabulary_id=(select vocabulary_id from drug_concept_stage where rownum=1) AND concept_code not in (select concept_code from rxe_replace) and concept_code like 'OMOP%' and invalid_reason is null;
update concept_relationship_stage SET vocabulary_id_1 = 'RxNorm Extension' WHERE vocabulary_id_1=(select vocabulary_id from drug_concept_stage where rownum=1) AND concept_code_1 in (select concept_code from concept_stage where vocabulary_id = 'RxNorm Extension');
update concept_relationship_stage SET vocabulary_id_2 = 'RxNorm Extension' WHERE vocabulary_id_2=(select vocabulary_id from drug_concept_stage where rownum=1) AND concept_code_2 in (select concept_code from concept_stage where vocabulary_id = 'RxNorm Extension');

commit;

-- insert mappings
insert into concept_relationship_stage(concept_code_1, vocabulary_id_1, concept_code_2, vocabulary_id_2, relationship_id, valid_start_date, valid_end_date, invalid_reason)
select 
  rxer.concept_code as concept_code_1,
  (select vocabulary_id from drug_concept_stage where rownum=1) as vocabulary_id_1,
  rxer.rxe_code as concept_code_2,
  'RxNorm Extension' as vocabulary_id_2,
  'Maps to' as relationship_id,
  (select latest_update from vocabulary v where v.vocabulary_id=(select vocabulary_id from drug_concept_stage where rownum=1)) as valid_start_date,
  to_date('2099-12-31', 'yyyy-mm-dd') as valid_end_date,
  null as invalid_reason
from rxe_replace rxer;

commit;

-- since now all the concepts in the base vocab are present in RxE and have mappings, so they are not standard
update concept_stage SET standard_concept = null WHERE vocabulary_id=(select vocabulary_id from drug_concept_stage where rownum=1);

commit;

-- drop temp table
drop table rxe_replace;
--return old names of dm+d
;
update concept_stage a set concept_name = (select concept_name from drug_concept_stage b where a.concept_code = b.CONCEPT_CODE)
where exists 
(select 1 from drug_concept_stage b where a.concept_code = b.CONCEPT_CODE)
;
commit
;
