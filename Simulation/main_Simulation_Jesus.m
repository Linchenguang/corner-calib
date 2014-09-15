% Main script for the synthetic simulations

% Simulated data for the Extrinsic Calibration of a 2D Lidar and a
% Monocular Camera based on Corner Structures without Pattern

% clear classes
clear;

% Main options:
WITHPLOTSCENE = false;
WITHRANSAC = false;
WITHPLOTCOST = true;

% Generate Rig (Camera) poses
% [R_w_c, t_w_c] = generate_random_poses( );
gen_config_file = fullfile( pwd, 'pose_gen.ini' );
[R_w_c, t_w_c, rand_ang_z, rand_ang_x] = generate_random_poses( gen_config_file ); % For debug purposes only
rand_ang_x = rad2deg( rand_ang_x );
rand_ang_z = rad2deg( rand_ang_z );
Nsamples = length(R_w_c);
corresp  = cell(2,3,Nsamples);

% Set Rig properties
rig_config_file = fullfile( pwd, 'rig.ini' );
rigOpts = readConfigFile( rig_config_file );
extractStructFields( rigOpts );
clear rigOpts
Rig = CSimRig( eye(3), zeros(3,1), R_c_s, t_c_s,... % Extrinsic options
               N, FOVd, scan_sd, d_range,... % Lidar options
               K, res, f, cam_sd ); % Camera options                

% trihedron = CTrihedron( LPattern );
trihedron = CTrihedron( LPattern, eye(3), [-0.5 -0.5 0]' );
corner = CCorner( expmap( [-1 +1 0], deg2rad(-45) ) );
checkerboard = CCheckerboard( RotationZ(deg2rad(45))*RotationY(deg2rad(45)) );
pattern = { trihedron, corner, checkerboard };

corner_corresp = cell(2,3,Nsamples);

tic
optim_config_file = fullfile( pwd, 'optim_config.ini' );
optimOpts = readConfigFile( optim_config_file );
extractStructFields( optimOpts );
clear optimOpts
triOptim = CTrihedronOptimization( K,...
    RANSAC_Rotation_threshold,...
    RANSAC_Translation_threshold,...
    debug_level, maxIters,...
    minParamChange, minErrorChange);
cornerOptim = CCornerOptimization( K,...
    debug_level, maxIters,...
    minParamChange, minErrorChange);

for i=1:Nsamples
    % Update reference (Camera) pose in Rig
    Rig.updatePose( R_w_c{i}, t_w_c{i} );
        
    % Correspondences for Kwak's algorithm
    corr_ = corner.getCorrespondence(Rig); 
    cornerOptim.stackObservation( corr_ );
    
    % Correspondences for Vasconcelos and Zhang's algorithm
    check_corresp{1,i} = checkerboard.p2D; 
    check_corresp{2,i} = checkerboard.getProjection( Rig.Camera );    
    check_corresp{3,i} = 1000 * cell2mat(checkerboard.getScan( Rig.Lidar ));
    
    % Correspondences for trihedron
    co_ = trihedron.getCorrespondence( Rig );
    triOptim.stackObservation( co_ );
    
    if WITHPLOTSCENE
        figure
        subplot(131)
        trihedron.plotScene(Rig.Camera, Rig.Lidar);
        subplot(132)
        corner.plotScene(Rig.Camera, Rig.Lidar);
        subplot(133)
        checkerboard.plotScene(Rig.Camera, Rig.Lidar);
        set(gcf,'units','normalized','position',[0 0 1 1]);
        keyboard
        close
    end
end

% ------------- Trihedron ----------------
triOptim.setInitialRotation( [ 0 -1  0
                               0  0 -1
                               1  0  0 ] ); % Updated in RANSAC
if WITHRANSAC
   triOptim.filterRotationRANSAC;
end
triOptim.disp_N_R_inliers;
R_c_s_nw = triOptim.optimizeRotation_NonWeighted;
R_c_s_dw = triOptim.optimizeRotation_DiagWeighted;
R_c_s_w  = triOptim.optimizeRotation_Weighted;
% R_c_s
% R_c_s_w
% R_c_s_dw
% R_c_s_nw

% Plot rotation cost function near GT
% triOptim.plotRotationCostFunction( Rig.R_c_s );

if WITHRANSAC
    triOptim.filterTranslationRANSAC( Rig.R_c_s ); % Should receive some estimated rotation
end
triOptim.disp_N_t_inliers;
triOptim.setInitialTranslation( Rig.t_c_s + 0.05*randn(3,1) );
t_3D_nw = triOptim.optimizeTranslation_3D_NonWeighted( Rig.R_c_s );
t_3D_w  = triOptim.optimizeTranslation_3D_Weighted( Rig.R_c_s );
t_2D_nw = triOptim.optimizeTranslation_2D_NonWeighted( Rig.R_c_s );
t_2D_w = triOptim.optimizeTranslation_2D_Weighted( Rig.R_c_s );
% t_3D_nw
% t_3D_w
% t_2D_nw

% Plot translation cost function near GT
% triOptim.plotTranslation_3D_CostFunction( Rig.R_c_s, Rig.t_c_s );

% ------------- Kwak -------------------
% Generate random input (near GT)
R_aux = Rig.R_c_s + randn(3,3)*0.08;
[U,S,V] = svd(R_aux);
Rt0 = [ U*V' , Rig.t_c_s + 0.05*randn(3,1) ];
% Optimize
cornerOptim.setInitialRotation( Rt0(1:3,1:3) );
cornerOptim.setInitialTranslation( Rt0(1:3,4) );
[R_k_nw, t_k_nw] = cornerOptim.optimizeRt_NonWeighted;
% [R_k_w,  t_k_w]  = cornerOptim.optimizeRt_Weighted;
[R_k_cw, t_k_cw] = cornerOptim.optimizeRt_ConstWeighted;
% [R_k_pw, t_k_pw] = cornerOptim.optimizeRt_PreWeighted;
[R_kC_nw, t_kC_nw] = cornerOptim.optimizeRt_C_NonWeighted;

% Check distance between optimization and initial point
fprintf('Kwak (NW): Change in rotation = %f\n',angularDistance(R_k_nw,Rt0(1:3,1:3)));
% fprintf('Kwak ( W): Change in rotation = %f\n',angularDistance(R_k_w, Rt0(1:3,1:3)));
fprintf('Kwak (CW): Change in rotation = %f\n',angularDistance(R_k_cw, Rt0(1:3,1:3)));
fprintf('Kwak-C (NW): Change in rotation = %f\n',angularDistance(R_kC_nw, Rt0(1:3,1:3)));
fprintf('Kwak (NW): Change in translation = %f\n',norm(t_k_nw - Rt0(1:3,4)));
% fprintf('Kwak ( W): Change in translation = %f\n',norm(t_k_w  - Rt0(1:3,4)));
fprintf('Kwak (CW): Change in translation = %f\n',norm(t_k_cw  - Rt0(1:3,4)));
fprintf('Kwak-C (NW): Change in translation = %f\n',norm(t_kC_nw  - Rt0(1:3,4)));
fprintf('\n\n')

% % ---------- Vasconcelos -------------------------
% [T_planes,lidar_points] = checkerboard.getCalibPlanes( Rig, check_corresp );
% [T, ~,~,~,~] = lccMinSol(T_planes,lidar_points);
% [T_z, ~,~,~,~] = lccZhang(T_planes, lidar_points);
% x_v = pose_inverse(T); x_v(1:3,4) = x_v(1:3,4)/1000;
% x_z = pose_inverse(T_z); x_z(1:3,4) = x_z(1:3,4)/1000;

% Compute hessian in convergence points for different methods
H_R = triOptim.FHes_Orthogonality( R_c_s_w );
H_t_3D = triOptim.FHes_3D_PlaneDistance( Rig.R_c_s, t_3D_w );
H_t_2D = triOptim.FHes_2D_LineDistance( Rig.R_c_s, t_2D_w );
H_Rt_k = cornerOptim.FHes_2D_LineDistance( [R_k_cw, t_k_cw] );
H_Rt_kC = cornerOptim.FHes_C_2D_LineDistance( [R_k_cw, t_k_cw] );

% Plot cost functions near GT
if WITHPLOTCOST
    figure('Name','Trihedron Rotation: Orthogonality cost function');
    title('Trihedron Rotation: Orthogonality cost function');
    triOptim.plotRotationCostFunction( Rig.R_c_s );
    
    figure('Name','Corner Rotation: 2D distance cost function');
    title('Corner Rotation: 2D distance cost function');
    cornerOptim.plotRotationCostFunction( Rig.R_c_s, Rig.t_c_s );
    
    figure('Name','Corner Rotation: 2D distance cost function (only center)');
    title('Corner Rotation: 2D distance cost function (only center)');
    cornerOptim.plotRotation_C_CostFunction( Rig.R_c_s, Rig.t_c_s );
    
    figure('Name','Trihedron Translation: 3D distance cost function');
    title('Trihedron Translation: 3D distance cost function');
    triOptim.plotTranslation_3D_CostFunction( Rig.R_c_s, Rig.t_c_s );
    
    figure('Name','Trihedron Translation: 2D distance cost function');
    title('Trihedron Translation: 2D distance cost function');
    triOptim.plotTranslation_2D_CostFunction( Rig.R_c_s, Rig.t_c_s );
    
    figure('Name','Corner Translation: 2D distance cost function');
    title('Corner Translation: 2D distance cost function');
    cornerOptim.plotTranslationCostFunction( Rig.R_c_s, Rig.t_c_s );
    
    figure('Name','Corner Translation: 2D distance cost function (only center)');
    title('Corner Translation: 2D distance cost function (only center)');
    cornerOptim.plotTranslation_C_CostFunction( Rig.R_c_s, Rig.t_c_s );
end

% ---------- Display the errors -------------------------
fprintf('(*) -> best current method\n');

fprintf('=============================================================\n');
%fprintf('Kwak translation error (m): \t %f \n', norm(x_w(:,4) - x_gt(:,4)) );
fprintf('(*) Trihedron (weighted) rotation error (deg): \t \t %f \n',...
    angularDistance(R_c_s_w,Rig.R_c_s) );
fprintf('Trihedron (diag-weighted) rotation error (deg): \t %f \n',...
    angularDistance(R_c_s_dw,Rig.R_c_s) );
fprintf('Trihedron (non-weighted) rotation error (deg): \t \t %f \n',...
    angularDistance(R_c_s_nw,Rig.R_c_s) );
fprintf('=============================================================\n');
fprintf('Trihedron (non-weighted, 3D) translation error (cm): \t %f \n',...
    norm(t_3D_nw-Rig.t_c_s)*100 );
fprintf('Trihedron (    weighted, 3D) translation error (cm): \t %f \n',...
    norm(t_3D_w-Rig.t_c_s)*100 );
fprintf('Trihedron (non-weighted, 2D) translation error (cm): \t %f \n',...
    norm(t_2D_nw-Rig.t_c_s)*100 );
fprintf('Trihedron (    weighted, 2D) translation error (cm): \t %f \n',...
    norm(t_2D_w-Rig.t_c_s)*100 );

fprintf('=============================================================\n');
fprintf('=============================================================\n');
% fprintf('    Kwak (      weighted) rotation error (deg): \t %f \n',   angularDistance(R_k_w, Rig.R_c_s) );
fprintf('    Kwak (  non-weighted) rotation error (deg): \t %f \n',   angularDistance(R_k_nw,Rig.R_c_s ));
fprintf('(*) Kwak (const-weighted) rotation error (deg): \t %f \n',   angularDistance(R_k_cw,Rig.R_c_s ));
fprintf('    Kwak-C (  non-weighted) rotation error (deg): \t %f \n',   angularDistance(R_kC_nw,Rig.R_c_s ));
fprintf('=============================================================\n');
% fprintf('    Kwak (      weighted) translation error (cm): \t %f \n', 100*norm(t_k_w  - Rig.t_c_s) );
fprintf('    Kwak (  non-weighted) translation error (cm): \t %f \n', 100*norm(t_k_nw - Rig.t_c_s) );
fprintf('(*) Kwak (const-weighted) translation error (cm): \t %f \n', 100*norm(t_k_cw - Rig.t_c_s) );
fprintf('    Kwak-C (  non-weighted) translation error (cm): \t %f \n', 100*norm(t_kC_nw - Rig.t_c_s) );

% fprintf('Vasconcelos translation error (cm): \t %f \n', 100 * norm(x_v(1:3,4) - x_gt(1:3,4)) );
% fprintf('Vasconcelos rotation error (deg): \t %f \n', angularDistance(x_v(1:3,1:3),x_gt(1:3,1:3)) );

% fprintf('Zhang translation error (cm): \t %f \n', 100 * norm(x_z(1:3,4) - x_gt(1:3,4)) );
% fprintf('Zhang rotation error (deg): \t %f \n', angularDistance(x_z(1:3,1:3),x_gt(1:3,1:3)) );

toc