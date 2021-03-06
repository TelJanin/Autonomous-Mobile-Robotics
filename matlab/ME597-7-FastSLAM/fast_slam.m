% Fast SLAM example
clear;clc;

% Time
Tf = 20;
dt = 0.5;
T = 0:dt:Tf;

% Initial Robot State
x0 = [0 0 0]';

% Control inputs
u = ones(2, length(T));
u(2,:)=0.3*u(2,:);

% Motion Disturbance model
R = [0.001 0 0; 
     0 0.001 0; 
     0 0 0.0001];
[RE, Re] = eig(R);

% Feature Map
M = 10;
map = 11*rand(2,M);
map(1,:) = map(1,:)-5.5; 
map(2,:) = map(2,:)-2; 


% Measurement model
rmax = 10;
thmax = pi/4;

% Feature initialization
newfeature = ones(M,1);

% Measurement noise
Qi = [0.0001 0; 
     0 0.0001];

[QiE, Qie] = eig(Qi);

% Number of particles
D = 100;
% Prior - known exactly
X = zeros(3,D);
X0 = X;

% Simulation Initializations
n = length(R(:,1)); % Number of vehicle states
xr = zeros(n,length(T)); % Vehicle states 
xr(:,1) = x0;
m = length(Qi(:,1)); % Number of measurements per feature 
N = n+m*M;
y = zeros(m*M,length(T)); % Measurements

% Particles
X = zeros(3,D); % Vehicle states
Xp = X; % Interim Vehicle states
mu = zeros(2,M,D); % Feature means
mup = mu; % Interim Feature means
S = zeros(2,2,M,D); % Feature covariances
Sp = S; % Interim feature covariances
% Initialization of Particle weights
w0 = 1/D; 
w = w0*ones(1,D);
    
%% Main loop
for t=2:length(T)
    %% Simulation
    % Select a motion disturbance
    e = RE*sqrt(Re)*randn(n,1);
    % Update robot state
    xr(:,t) = [xr(1,t-1)+u(1,t)*cos(xr(3,t-1))*dt;
              xr(2,t-1)+u(1,t)*sin(xr(3,t-1))*dt;
              xr(3,t-1)+u(2,t)*dt] + e;

    % Define features that can be measured
    meas_ind = [];
    for i=1:M
        if(inview(map(:,i),xr(:,t),rmax,thmax))
            meas_ind=[meas_ind,i];
        end
    end
    
    % Take measurements
    for i = meas_ind
        % Select a measurement disturbance
        delta = QiE*sqrt(Qie)*randn(m,1);
        % Determine measurement, add to measurement vector
        y(2*(i-1)+1:2*i,t) = [sqrt((map(1,i)-xr(1,t))^2 + (map(2,i)-xr(2,t))^2);
            atan2(map(2,i)-xr(2,t),map(1,i)-xr(1,t))-xr(3,t)] + delta;
    end
    
    %% Fast SLAM Filter Estimation

    % For each particle
    for d=1:D
        % Select a motion disturbance
        em = 2*RE*sqrt(Re)*randn(n,1);
        % Update full state
        Xp(:,d) = [X(1,d)+u(1,t)*cos(X(3,d))*dt;
                  X(2,d)+u(1,t)*sin(X(3,d))*dt;
                  X(3,d)+u(2,t)*dt] + em;

        % For each feature measured
        j=1; clear hmuw Qw;
        yw = [];
        for i=meas_ind      
            if (newfeature(i) == 1)
                % Feature initialization
                mup(1,i,d) = Xp(1,d)+y(2*(i-1)+1,t)*cos(y(2*i,t)+Xp(3,d));
                mup(2,i,d) = Xp(2,d)+y(2*(i-1)+1,t)*sin(y(2*i,t)+Xp(3,d));
                % Predicted range
                dx = mup(1,i,d)-Xp(1,d);
                dy = mup(2,i,d)-Xp(2,d);
                rp = sqrt((dx)^2+(dy)^2);
                % Calculate Jacobian
                Ht = [ dx/rp dy/rp; -dy/rp^2 dx/rp^2];
                Sp(:,:,i,d) = inv(Ht)*Qi*inv(Ht)';
                w(d) = w0;
            else
                % Measurement processing
                % Predicted range
                dx = mup(1,i,d)-Xp(1,d);
                dy = mup(2,i,d)-Xp(2,d);
                rp = sqrt((dx)^2+(dy)^2);
                % Calculate Jacobian
                Ht = [ dx/rp dy/rp; -dy/rp^2 dx/rp^2];
                % Calculate Innovation
                I = y(2*(i-1)+1:2*i,t)-[rp; (atan2(dy,dx) - Xp(3,d))];

                % Measurement update
                Q = Ht*Sp(:,:,i,d)*Ht' + Qi;
                K = Sp(:,:,i,d)*Ht'*inv(Q);
                mup(:,i,d) = mup(:,i,d) + K*I;
                Sp(:,:,i,d) = (eye(2)-K*Ht)*Sp(:,:,i,d);

                % Create full Innovation and Q for weighting
                yw = [yw'; y(2*(i-1)+1:2*i,t)]';
                hmuw(2*(j-1)+1:2*j) = [rp;(atan2(dy,dx) - Xp(3,d))];
                Qw(2*(j-1)+1:2*j,2*(j-1)+1:2*j) = 100*Q;
                j=j+1;
            end
        end
        
        %Calculate weight
        w(d) = w0;
        if (exist('Qw'))
            [QwE,Qwe] = eig(Qw);
            w(d) = mvnpdf(yw,hmuw,Qw);
        end
    end
    
    % Eliminate initialization of previously measured features
    newfeature(meas_ind) = 0;
        
    % Resampling
    W = cumsum(w);

    % In case of numerical failure, set all weights equal and continue
%     if (W(end) == 0)
%         W = 0:w0:1;
%         W = W(1:D);
%     end
    % Resample and copy all data to new particle set
    for d=1:D
        seed = W(end)*rand(1);
        cur = find(W>seed,1);
        X(:,d) = Xp(:,cur);
        mu(:,:,d) = mup(:,:,cur);
        S(:,:,:,d) = Sp(:,:,:,cur);
    end
    
    muParticle = mean(X');
    mu_S(:,t) = muParticle;

    %% Plot results
    figure(1);clf; hold on;
    plot(map(1,:),map(2,:),'go', 'MarkerSize',10,'LineWidth',2);
    plot(xr(1,1:t),xr(2,1:t), 'ro--')
    plot([xr(1,t) xr(1,t)+1*cos(xr(3,t))],[xr(2,t) xr(2,t)+1*sin(xr(3,t))], 'r-')
    %plot(mu_S(1,1:t),mu_S(2,1:t), 'bx--')
    %plot([mu_S(1,t) mu_S(1,t)+1*cos(mu_S(3,t))],[mu_S(2,t) mu_S(2,t)+1*sin(mu_S(3,t))], 'b-')
    for i=meas_ind
        plot([xr(1,t) xr(1,t)+y(2*(i-1)+1,t)*cos(y(2*i,t)+xr(3,t))], [xr(2,t) xr(2,t)+y(2*(i-1)+1,t)*sin(y(2*i,t)+xr(3,t))], 'c');
    end
    for d=1:D
        plot(X(1,d),X(2,d),'b.');
        for j = 1:M
            if (~newfeature(j))
                plot(mu(1,j,d),mu(2,j,d),'r.');
                %error_ellipse(S_pos,mu_pos,0.95);
            end
        end
    end
    axis equal
    %axis([-6 6 -2 10])
    title('FastSLAM with Range & Bearing Measurements')
    %F(t-1) = getframe(gcf);
end

