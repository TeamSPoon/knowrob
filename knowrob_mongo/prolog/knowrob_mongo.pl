%%
%% Copyright (C) 2013 by Moritz Tenorth
%%
%% This program is free software; you can redistribute it and/or modify
%% it under the terms of the GNU General Public License as published by
%% the Free Software Foundation; either version 3 of the License, or
%% (at your option) any later version.
%%
%% This program is distributed in the hope that it will be useful,
%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%% GNU General Public License for more details.
%%
%% You should have received a copy of the GNU General Public License
%% along with this program.  If not, see <http://www.gnu.org/licenses/>.
%%

:- module(knowrob_mongo,
    [
      mng_latest_designator_before_time/3,
      mng_designator_type/2,
      mng_designator_props/3,
      mng_desig_matches/2,
      mng_obj_pose_by_desig/2,

      mng_lookup_transform/4,
      mng_transform_pose/5,

      mng_timestamp/2,

      mng_robot_pose/2,
      mng_robot_pose_at_time/4,
      mng_comp_pose/2,
      mng_comp_pose_at_time/4,

      obj_blocked_by_in_camera/4,
      obj_visible_in_camera/3
    ]).

:- use_module(library('semweb/rdfs')).
:- use_module(library('owl_parser')).
:- use_module(library('owl')).
:- use_module(library('rdfs_computable')).
:- use_module(library('jpl')).
:- use_module(library('knowrob_objects')).
:- use_module(library('knowrob_perception')).
:- use_module(library('knowrob_coordinates')).
:- use_module(library('srdl2')).


:-  rdf_meta
    mng_lookup_transform(+,+,r,-),
    mng_latest_designator_before_time(r,-,-),

    mng_robot_pose(r, r),
    mng_robot_pose_at_time(r, +, r, r),
    mng_comp_pose(r, r),
    mng_comp_pose_at_time(r, +, r, r),

    mng_timestamp(r, r),

    mng_desig_matches(r, +),
    mng_obj_pose_by_desig(r,r),
    mng_designator_props(r,?),
    mng_designator_type(r,?),

    obj_blocked_by_in_camera(r, r, r, r),
    obj_visible_in_camera(r, r, r).


:- rdf_db:rdf_register_ns(rdf, 'http://www.w3.org/1999/02/22-rdf-syntax-ns#', [keep(true)]).
:- rdf_db:rdf_register_ns(owl, 'http://www.w3.org/2002/07/owl#', [keep(true)]).
:- rdf_db:rdf_register_ns(knowrob, 'http://knowrob.org/kb/knowrob.owl#', [keep(true)]).
:- rdf_db:rdf_register_ns(xsd, 'http://www.w3.org/2001/XMLSchema#', [keep(true)]).
:- rdf_db:rdf_register_ns(srdl2comp, 'http://knowrob.org/kb/srdl2-comp.owl#', [keep(true)]).



mongo_interface :-
    mongo_interface(_).

:- assert(mng_interface(fail)).
mongo_interface(DB) :-
    mng_interface(fail),
    jpl_new('org.knowrob.interfaces.mongo.MongoDBInterface', [], DB),
    retract(mng_interface(fail)),
    assert(mng_interface(DB)),!.
mongo_interface(DB) :-
    mng_interface(DB).


% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % %
% Designator integration
%

%% mng_latest_designator_before_time(+TimePoint, -Type, -Pose) is nondet.
%
% Read the pose of the latest designator of type 'Type' before 'TimePoint'
%
% @param TimePoint  Instance of knowrob:TimePoint
% @param Type       'Type' property of the designator
% @param PoseList   Object pose from designator as list[16]
%
mng_latest_designator_before_time(TimePoint, Type, PoseList) :-

  rdf_split_url(_, TimePointLocal, TimePoint),
  atom_concat('timepoint_', TimeAtom, TimePointLocal),
  term_to_atom(Time, TimeAtom),

  mongo_interface(DB),
  jpl_call(DB, 'latestUIMAPerceptionBefore', [Time], Designator),
  jpl_call(Designator, 'get', ['_designator_type'], Type),
  jpl_call(Designator, 'get', ['POSE-ON-PLANE'], StampedPoseString),
  jpl_call('com.mongodb.util.JSON', parse, [StampedPoseString], StampedPoseParsed), 
  jpl_new('org.knowrob.interfaces.mongo.types.PoseStamped', [], StampedPose), 
  jpl_call(StampedPose, readFromDBObject, [StampedPoseParsed], StampedPose), 
  jpl_call(StampedPose, 'getMatrix4d', [], PoseMatrix4d),  
  knowrob_coordinates:matrix4d_to_list(PoseMatrix4d, PoseList).



%% mng_obj_pose_by_desig(+Obj, -Pose) is nondet.
% 
% Determine object pose based on the POSE property of a linked designator
%
% @param Obj   Object instance
% @param Pose  Instance of a Perception
% 
mng_obj_pose_by_desig(Obj, Pose) :-

  % TODO: avoid multiple creation of pose instances
  rdf_has(Obj, knowrob:designator, Designator),
  mng_designator_props(Designator, 'POSE', Pose).



%% mng_designator_type(+Designator, ?Type) is nondet.
%
% Read the type of a logged designator by its ID
% 
% @param Designator  Instance of a designator, having its ID as local part of the IRI
% @param Type        Type of the designator
% 
mng_designator_type(Designator, Type) :-

  rdf_split_url(_, DesigID, Designator),

  mongo_interface(DB),
  jpl_call(DB, 'getDesignatorByID', [DesigID], DesigJava),

  jpl_call(DesigJava, 'getType', [], Type).


%% mng_designator_props(+Designator, ?Prop, ?Value) is nondet.
%
% Read the properties of a logged designator by its ID
%
% @param Designator  Instance of a designator, having its ID as local part of the IRI
% @param Prop        Property slot of the designator
% @param Value       Value slot of the designator
% 
mng_designator_props(Designator, Prop, Value) :-

  rdf_split_url(_, DesigID, Designator),

  mongo_interface(DB),
  jpl_call(DB, 'getDesignatorByID', [DesigID], DesigJava),

  jpl_call(DesigJava, 'keySet', [], PropsSet),
  jpl_set_element(PropsSet, Prop),

  once(mng_desig_get_value(Designator, DesigJava, Prop, Value)).



%% mng_desig_get_value(?Designator, +DesigJava, +Prop, -Value).
% 
% Internal helper method: handle the different kinds of designator values
%
% @param Designator  Designator instance
% @param DesigJava   Java handle of a org.knowrob.mongo.types.Designator object
% @param Prop        Designator property
% @param Value       Value extracted from the designator, e.g. a primitive value
%                    (string, float etc), the handle of a nested designator object,
%                    or an instance of a RotationMatrix3D of an object pose
%

% create designator instance for child-designators
mng_desig_get_value(_Designator, DesigJava, Prop, Value) :-
  jpl_call(DesigJava, 'get', [Prop], ValIn),
  jpl_ref_to_type(ValIn,  class([org,knowrob,interfaces,mongo,types],['Designator'])),
  Value=ValIn. % TODO

% create observation of the object to which the designator is attached
mng_desig_get_value(Designator, DesigJava, Prop, Pose) :-

  jpl_call(DesigJava, 'get', [Prop], PoseStamped),
  jpl_ref_to_type(PoseStamped,  class([org,knowrob,interfaces,mongo,types],['PoseStamped'])),

  % find out which object we are talking about
  rdf_has(Obj, knowrob:designator, Designator),

  % get pose time
  jpl_get(PoseStamped, 'header', Header),
  jpl_get(Header, 'stamp', Stamp),
  jpl_get(Stamp,  'secs', TimeSecs),
  term_to_atom(TimeSecs, TimeSecsAtom),
  atom_concat('http://knowrob.org/kb/knowrob_mongo.owl#timepoint_', TimeSecsAtom, PoseTimePoint),

  % transform into /map
  jpl_call(PoseStamped, 'getMatrix4d', [], PoseMatrix4d),
  jpl_get(Header, 'frame_id', SourceFrame),
  knowrob_coordinates:matrix4d_to_list(PoseMatrix4d, PoseListIn),
  mng_transform_pose(PoseListIn, SourceFrame, '/map', PoseTimePoint, PoseListOut),
  create_pose(PoseListOut, Pose),

  % determine detection type (e.g. perception)
  jpl_call(DesigJava, 'getDetectionType', [], DetectionType),

  % create perception instance attached to the object this designator belongs to
  atom_concat('http://knowrob.org/kb/knowrob.owl#', DetectionType, DClass),
  rdf_instance_from_class(DClass, Detection),
  set_object_perception(Obj, Detection),
  rdf_assert(Detection, knowrob:eventOccursAt, Pose),

  rdf_assert(PoseTimePoint, rdf:type, 'http://knowrob.org/kb/knowrob.owl#TimePoint'),
  rdf_assert(Detection, knowrob:startTime, PoseTimePoint).

% just return the value for other properties
mng_desig_get_value(_Designator, DesigJava, Prop, Value) :-
  jpl_call(DesigJava, 'get', [Prop], Value).




% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % %
% Tf integration
%


%% mng_lookup_transform(+Target, +Source, +TimePoint, -Transform) is nondet.
%
% Determine the transform from Source to Target at TimePoint based on the logged
% tf data.
% 
% @param Target     Target frame ID
% @param Source     Source frame ID
% @param TimePoint  Instance of knowrob:TimePoint
% @param Transform  Transformation matrix as list[16]
%
mng_lookup_transform(Target, Source, TimePoint, Transform) :-

  rdf_split_url(_, TimePointLocal, TimePoint),
  atom_concat('timepoint_', TimeAtom, TimePointLocal),
  term_to_atom(Time, TimeAtom),

  mongo_interface(DB),
  jpl_call(DB, 'lookupTransform', [Target, Source, Time], StampedTransform),

  jpl_call(StampedTransform, 'getMatrix4', [], TransformMatrix4d),
  knowrob_coordinates:matrix4d_to_list(TransformMatrix4d, Transform).


%% mng_transform_pose(+PoseListIn, +SourceFrame, +TargetFrame, +TimePoint, -PoseListOut) is nondet.
% 
% Transform PoseListIn from SourceFrame into TargetFrame based on the logged tf data.
% 
% @param PoseListIn    Pose matrix in SourceFrame to be transformed into TargetFrame, as row-based list[16]
% @param SourceFrame   Source frame ID
% @param TargetFrame   Target frame ID
% @param TimePoint     Instance of knowrob:TimePoint
% @param PoseListOut   Pose matrix as row-based list[16]
%
mng_transform_pose(PoseListIn, SourceFrame, TargetFrame, TimePoint, PoseListOut) :-

  rdf_split_url(_, TimePointLocal, TimePoint),
  atom_concat('timepoint_', TimeAtom, TimePointLocal),
  term_to_atom(Time, TimeAtom),
  TimeInt is round(Time),

  knowrob_coordinates:list_to_matrix4d(PoseListIn, MatrixIn),
  jpl_new('tfjava.Stamped', [MatrixIn, SourceFrame, TimeInt], StampedIn),

  knowrob_coordinates:list_to_matrix4d([1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1], MatrixOut),
  jpl_new('tfjava.Stamped', [MatrixOut, '/base_link', TimeInt], StampedOut),

  mongo_interface(DB),
  jpl_call(DB, 'transformPose', [TargetFrame, StampedIn, StampedOut], @(true)),
  
  jpl_call(StampedOut, 'getData', [], MatrixOut2),
  knowrob_coordinates:matrix4d_to_list(MatrixOut2, PoseListOut).

%% mng_timestamp(+Date, -Stamp) is nondet.
%
% Computes a timestamp that corresponds to the specified date.
% date format must be as follows: "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
%
% @param Date        String representation of a date
% @param Stamp       Floating point timestamp that represents the date
%
mng_timestamp(Date, Stamp) :-
  mongo_interface(DB),
  jpl_call(DB, 'getMongoTimestamp', [Date], Stamp).



%% mng_robot_pose(+Robot, -Pose) is nondet.
%
% Compute the pose of all components of the robot at the current point in time.
%
% @param Robot        Instance of a robot in SRDL
% @param Pose         Instance of a knowrob:RotationMatrix3D with the pose data
%
mng_robot_pose(Robot, Pose) :-
  get_timepoint(TimePoint),
  mng_robot_pose_at_time(Robot, '/map', TimePoint, Pose).


%% mng_robot_pose_at_time(Robot, TargetFrame, TimePoint, Pose) is nondet.
%
% Compute the pose of all components of the robot at the given point in time.
%
% @param Robot        Instance of a robot in SRDL
% @param TargetFrame  Atom with tf frame ID in which the pose shall be returned (e.g. '/map')
% @param TimePoint    Instance of knowrob:TimePoint
% @param Pose         Instance of a knowrob:RotationMatrix3D with the pose data
%
mng_robot_pose_at_time(Robot, TargetFrame, TimePoint, Pose) :-

  findall(S, (sub_component(Robot, S),
              owl_individual_of(S, srdl2comp:'UrdfLink')), Ss),

  sort(Ss, Ssorted),
  findall(P, (member(Sub, Ssorted),mng_comp_pose_at_time(Sub, TargetFrame, TimePoint, P)), Ps),

  nth0(0, Ps, Pose).



%% mng_comp_pose(+RobotPart, -Pose) is nondet.
%
% Read the pose of RobotPart in /map coordinates from logged tf data, default to 'now'
%
% @param RobotPart  Instance of a robot part with the 'urdfName' property set
% @param Pose       Instance of a knowrob:RotationMatrix3D with the pose data
%
mng_comp_pose(RobotPart, Pose) :-

  get_timepoint(TimePoint),
  mng_comp_pose_at_time(RobotPart, '/map', TimePoint, Pose).


%% mng_comp_pose_at_time(+RobotPart, +TargetFrame, +TimePoint, -Pose) is nondet.
%
% Read the pose of RobotPart in the given coordinate frame from logged tf data
%
% @param RobotPart    Instance of a robot part with the 'urdfName' property set
% @param TargetFrame  Atom with tf frame ID in which the pose shall be returned (e.g. '/map')
% @param TimePoint    Instance of knowrob:TimePoint
% @param Pose         Instance of a knowrob:RotationMatrix3D with the pose data
%
mng_comp_pose_at_time(RobotPart, TargetFrame, TimePoint, Pose) :-

  owl_has(RobotPart, 'http://knowrob.org/kb/srdl2-comp.owl#urdfName', literal(SourceFrameID)),
  atom_concat('/', SourceFrameID, SourceFrame),

  mng_obj_pose_at_time(RobotPart, SourceFrame, TargetFrame, TimePoint, Pose).



%% mng_obj_pose_at_time(+Obj, +SourceFrame, +TargetFrame, +TimePoint, -Pose) is nondet.
%
% Read the pose of Obj and transform it into the coordinates given by
% TargetFrame  based on logged tf data
%
% @param Obj          Object instance
% @param SourceFrame  Atom with tf frame ID in what the object's pose is given
% @param TargetFrame  Atom with tf frame ID in which the pose shall be returned (e.g. '/map')
% @param TimePoint    Instance of knowrob:TimePoint
% @param Pose         Instance of a knowrob:RotationMatrix3D with the pose data
%
mng_obj_pose_at_time(Obj, SourceFrame, TargetFrame, TimePoint, Pose) :-

  % read object pose in original coordinates at TimePoint
  % MT: deactivated since, when called the second time, this will return different
  %     results because the pose is asserted below
%   (object_pose_at_time(Obj, TimePoint, PoseListIn)
%      -> true ;
        PoseListIn = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
%         ),

  mng_transform_pose(PoseListIn, SourceFrame, TargetFrame, TimePoint, PoseListOut),
  create_pose(PoseListOut, Pose),
  rdf_assert(Pose, knowrob:tfFrame, TargetFrame),

  rdf_instance_from_class('http://knowrob.org/kb/knowrob.owl#Proprioception', Perception),
  rdf_assert(Perception, knowrob:startTime, TimePoint),

  set_object_perception(Obj, Perception),
  rdf_assert(Perception, knowrob:eventOccursAt, Pose),

  % set time point for pose,
  rdf_assert(Perception, knowrob:startTime, TimePoint).







% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % %
% Higher-level reasoning methods
%

%% obj_visible_in_camera(+Obj, ?Camera, +TimePoint) is nondet.
%
% Check if Obj is visible by Camera at time TimePoint by reading the camera
% properties from the robot's SRDL description and computing whether the
% object center is inside the view frustrum.
%
% @param Obj        Instance of an object in the scene
% @param Camera     Instance of an srdl2comp:Camera
% @param TimePoint  Instance of a knowrob:TimePoint at which the scene is to be evaluated
% 
obj_visible_in_camera(Obj, Camera, TimePoint) :-

  findall(Camera, owl_individual_of(Camera, srdl2comp:'Camera'), Cameras),
  member(Camera, Cameras),

  % Read camera properties: horizontal field of view, aspect ratio -> vertical field of view
  once(owl_has(Camera, srdl2comp:hfov, literal(type(_, HFOVa)))),
  term_to_atom(HFOV, HFOVa),

  once(owl_has(Camera, srdl2comp:imageSizeX, literal(type(_, ImgXa)))),
  term_to_atom(ImgX, ImgXa),

  once(owl_has(Camera, srdl2comp:imageSizeY, literal(type(_, ImgYa)))),
  term_to_atom(ImgY, ImgYa),

  VFOV is ImgY / ImgX * HFOV,


  % Read object pose w.r.t. camera
  once(owl_has(Camera, 'http://knowrob.org/kb/srdl2-comp.owl#urdfName', literal(CamFrameID))),
  atom_concat('/', CamFrameID, CamFrame),

  % TODO: mng_latest_designator_before_time does not refer to Obj
  (object_pose_at_time(Obj, TimePoint, PoseListObj); mng_latest_designator_before_time(TimePoint, 'object', PoseListObj)),
  mng_transform_pose(PoseListObj, '/map', CamFrame, TimePoint, RelObjPose),

  RelObjPose = [_,_,_,ObjX,_,_,_,ObjY,_,_,_,ObjZ,_,_,_,_],

  BearingX is atan2(ObjY, ObjX),
  BearingY is atan2(ObjZ, ObjX),

  abs(BearingX) < HFOV/2,
  abs(BearingY) < VFOV/2.




%% obj_blocked_by_in_camera(?Obj, ?Blocker, ?Camera, +TimePoint) is nondet.
% 
% Check if the view on Obj from Camera at time TimePoint is blocked by object
% Blocker by reading the camera properties from the robot's SRDL description
% and by computing whether the difference in bearing between the two objects'
% center points from the camera viewpoint is less than ten degrees.
%
% @param Obj        Instance of an object in the scene
% @param Blocker    Instance of an object in the scene
% @param Camera     Instance of an srdl2comp:Camera
% @param TimePoint  Instance of a knowrob:TimePoint at which the scene is to be evaluated
% 
obj_blocked_by_in_camera(Obj, Blocker, Camera, TimePoint) :-

  findall(Camera, owl_individual_of(Camera, srdl2comp:'Camera'), Cameras),
  member(Camera, Cameras),

  % Read camera frame ID
  once(owl_has(Camera, 'http://knowrob.org/kb/srdl2-comp.owl#urdfName', literal(CamFrameID))),
  atom_concat('/', CamFrameID, CamFrame),


  % Read object pose w.r.t. camera
  (object_pose_at_time(Obj, TimePoint, PoseListObj); mng_latest_designator_before_time(TimePoint, 'object', PoseListObj)),
  mng_transform_pose(PoseListObj, '/map', CamFrame, TimePoint, ObjPoseInCamFrame),
  ObjPoseInCamFrame = [_,_,_,ObjX,_,_,_,ObjY,_,_,_,ObjZ,_,_,_,_],
  ObjBearingX is atan2(ObjY, ObjX),
  ObjBearingY is atan2(ObjZ, ObjX),

  % debug
%   ObjXDeg is ObjBearingX /2 /pi * 360,
%   ObjYDeg is ObjBearingY /2 /pi * 360,

  % Read poses of blocking robot parts w.r.t. camera
  sub_component('http://knowrob.org/kb/PR2.owl#PR2Robot1', Blocker),
  rdfs_individual_of(Blocker, 'http://knowrob.org/kb/srdl2-comp.owl#UrdfLink'),
  owl_has(Blocker, 'http://knowrob.org/kb/srdl2-comp.owl#urdfName', literal(PartFrameID)),
  atom_concat('/', PartFrameID, PartFrame),

%   print(PartFrame),
  % transform identity pose from robot part frame to camera frame
  mng_transform_pose([1,0,0,0,  0,1,0,0,  0,0,1,0,  0,0,0,1], PartFrame,
                     CamFrame, TimePoint, BlockerPoseInCamFrame),
  BlockerPoseInCamFrame = [_,_,_,BlkX,_,_,_,BlkY,_,_,_,BlkZ,_,_,_,_],
  BlkBearingX is atan2(BlkY, BlkX),
  BlkBearingY is atan2(BlkZ, BlkX),

  % debug
%   BlkXDeg is BlkBearingX /2 /pi * 360,
%   BlkYDeg is BlkBearingY /2 /pi * 360,

  abs(ObjBearingX - BlkBearingX) < 10/360 * 2 * pi,
  abs(ObjBearingY - BlkBearingY) < 10/360 * 2 * pi.



% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % %
%
% designator matches predicate 
%


%% mng_desig_matches(?Designator, +QueryPattern) is nondet.
%
% This predicate allows to retrieve designators from the log database that
% match a query pattern given as nested lists of key-value pairs. An example
% of such a query pattern may look like 
% [an, action, [type, navigation], [goal, [a, location, [to, see], [object_acted_on, [type, 'PANCAKEMIX']]]]]
%
% @param Designator    Designator instance that matches the pattern
% @param QueryPattern  Query pattern as nested lists
% 
mng_desig_matches(Designator, QueryPattern) :-

  % convert query pattern into list of query strings suitable for MongoDB queries
  desig_list_to_query(QueryPattern, 'designator', QueryStrings),
  pairs_keys_values(QueryStrings, QueryKeys, QueryValues),

  jpl_list_to_array(QueryKeys, QueryKeysArr),
  jpl_list_to_array(QueryValues, QueryValuesArr),
  
  % send MongoDB query:
  mongo_interface(DB),
  jpl_call(DB, 'getDesignatorsByPattern', [QueryKeysArr, QueryValuesArr], DesigJavaArr),

  jpl_array_to_list(DesigJavaArr, DesigJavaList),
  
  member(DesigJava, DesigJavaList),
  jpl_call(DesigJava, 'get', ['_id'], DesigID),
  rdf_split_url('http://knowrob.org/kb/cram_log.owl#', DesigID, Designator).


%% desig_list_to_query(+ConstrList, +Prefix, -QueryStringList)
%
% Generate a list of query strings that can be used to send queries
% to MongoDB. The keys are chained hierarchically using the dot
% notation. Both keys and values are converted by the lispify_desig
% predicate that, by default, converts them to UPPERCASE.
%
% @param ConstrList       List of constraints of the form [Key, Val], while Val may either be an atom or a nested list
% @param Prefix           Prefix to be used for constructing the resulting query strings
% @param QueryStringList  List of key-value pairs to be used in a MongoDB query, e.g.  'producer.company'-'ABC123'
%

% special list starts:
desig_list_to_query(DesigList, Prefix, QueryStringList) :-

    once( (member(Pre, [[an, action], [an, object], [a, location]]),
           append(Pre, Rest, DesigList)) ),

    findall(QSL, (member(Desig, Rest),
                  once(desig_list_to_query(Desig, Prefix, QSL))), QueryStringLists),

    flatten(QueryStringLists, QueryStringList).


% simple case: normal key/value pair
desig_list_to_query([Key, Val], Prefix, Str-LispVal) :-
    atom(Key), atom(Val),

    once(lispify_desig(Key, LispKey)),
    once(lispify_desig(Val, LispVal)),

    atomic_list_concat([Prefix, '.', LispKey], Str).


% recursive case: value is a list, we have to iterate
desig_list_to_query([Key, Val], Prefix, QueryStringList) :-
    atom(Key), is_list(Val),

    once(lispify_desig(Key, LispKey)),
    atomic_list_concat([Prefix, '.', LispKey], NewPrefix),
    
    desig_list_to_query(Val, NewPrefix, QueryStringList).
    


%% lispify_desig(?QueryVal, ?LispVal) is det.
%
% Convert values in the query language to the corresponding Lisp
% identifiers. Special transforms can be defined, while the default
% is just to convert the values to UPPERCASE.
%
% @param QueryVal  Identifier in the query language
% @param LispVal   Identifier used in Lisp and in the MongoDB logs
%

lispify_desig('object_acted_on', 'OBJ').

% default: do not modify value
lispify_desig(A, CapA) :-
  upcase_atom(A, CapA).


