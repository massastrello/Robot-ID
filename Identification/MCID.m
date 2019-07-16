clear DATA

options = optimoptions('fmincon',...
                        'Algorithm', 'sqp',...
                        'MaxFunctionEvaluations', 1*1e3);

                    
qid = qint';%(:,1:1/ts:end)';%
qdid = qdint';%(:,1:1/ts:end)';
qddid = qddint';%(:,1:1/ts:end)';
N = length(qid);
Wnp = computeRegression(qid,qdid,qddid,n,N);
tau =  Wnp*gammaR_ref;

par = size(Wnp,2); 

%noise std
bn = .001;
tn = 1;

nMC = 250;
m = 1000;

temp = nMC;
DATA(nMC) = struct();
iter = N-m+1;
i = 1;
k = 1;
while i <= nMC
    i
    k
    %
    %noise 
    rng(i)
    nq = bn*randn(N,n);
    rng(i+nMC)
    ndq = 2*bn*randn(N,n);
    rng(rng(i+2*nMC))
    nddq = 2*bn*randn(N,n);
    rng(i + 4*nMC)
    ntau = tn*randn(n*N,1);
    % noisy traj.
    qS = qid + nq;
    qdS = qdid + ndq;
    qddS = qddid + nddq;
    % regression matrix
    WnS = computeRegression(qS,qdS,qddS,n,N); 
    tauS = tau + ntau;
    We = [WnS, tauS];
    S = (We'*We)/(n*N);
    % oneshot Frisch
    A = OLS(S,par+1,-1);
    Am = min(A(1:end-1,:),[],2);
    AM = max(A(1:end-1,:),[],2);
    % BBRF
    X0=We(1:m,:);
    S0=(X0'*X0)/length(X0);A0=OLS(S0,par+1,-1);
    l0=min(A0(1:end-1,:),[],2);u0=max(A0(1:end-1,:),[],2);
    l0(1:5) = [max(0,Am(1));max(0,Am(2));...
               max(0,Am(3));max(0,Am(4));max(0,Am(5))];
    %
    idx0 = l0>u0;
    idx1 = Am>gammaR_ref;
    idx2 = AM<gammaR_ref;
    if any(idx0)||any(idx1)||any(idx2)
        disp('Err Initial Simplex: something weird happened')
        i = i + 1;
        nMC = nMC + 1;
        continue
    end
    lb = zeros(length(l0),iter); lb(:,1) = l0;
    ub = zeros(length(u0),iter); ub(:,1) = u0;
    %
    for j = 2:iter
        Xj = We(j:j+m,:);
        Sj = (Xj'*Xj)/m;
        Aj = OLS(Sj,par+1,-1);
        lb(:,j) = max(lb(:,j-1),min(Aj(1:end-1,:),[],2));
        ub(:,j) = min(ub(:,j-1),max(Aj(1:end-1,:),[],2));
        idx = lb(:,j)>ub(:,j);
        if any(idx)
            lb(:,j) = lb(:,j-1);
            ub(:,j) = ub(:,j-1);
        end
    end
    %{
    figure(5)
    for k = 1:9
        subplot(330+k)
        semilogx(lb(k,:),'LineWidth',2)
        hold on
        
        semilogx(ub(k,:),'LineWidth',2)
         semilogx([1,iter],[gammaR_ref(k),gammaR_ref(k)],'--k','LineWidth',1)
        hold off
        box on
        ylabel(['\theta_',num2str(k)])
    end
    drawnow
    %}
    idx = lb(:,j)>ub(:,j);
    if any(idx)
        disp('BBRF ERROR')
        break
    end
    % select point
    x0=0.5.*(lb(:,end)+ub(:,end));
    x=fmincon(@(x) selection_cost(x,WnS,tauS),x0,[],[],[],[],lb(:,end),ub(:,end),[],options);
    e_x = abs(gammaR_ref-x);
    % reconstruct torques
    tau_x = reshape(WnS*x,n,length(qid));
    tauS_flat = reshape(tauS,n,length(qid));
    % reconstruction error
    e_tau = tau_x'-tauS_flat';
    norm_e_tau = sqrt(e_tau(:,1).^2 + e_tau(:,2).^2);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % save data
    DATA(k).S = S;
    DATA(k).A = A;
    DATA(k).Am = Am;
    DATA(k).AM = AM;
    DATA(k).lb = lb;
    DATA(k).ub = ub;
    DATA(k).x = x;
    DATA(k).e_x = e_x;
    DATA(k).tau_x = tau_x;
    DATA(k).tauS_flat = tauS_flat;
    DATA(k).e_tau = e_tau;
    DATA(k).norm_e_tau = norm_e_tau;
    %
    i = i+1;
    k = k+1;
    %
end
%% FCNs
function IDX = selection_cost(x,Wns,taus)
IDX = norm(Wns*x-taus) + norm(x);
end