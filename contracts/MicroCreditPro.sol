/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MicroCreditPro {

    // --- ÉVÉNEMENTS (Pour ton Frontend React) ---
    event DemandeCreee(uint256 indexed id, address indexed emprunteur, uint256 montant);
    event InvestissementRecu(uint256 indexed id, address indexed investisseur, uint256 montant);
    event PretTotalementFinance(uint256 indexed id);
    event RemboursementRecu(uint256 indexed id, address indexed emprunteur, uint256 montant);
    event RetraitGainsEffectue(uint256 indexed id, address indexed investisseur, uint256 montant);

    struct Pret {
        address emprunteur;
        uint256 montantDemande;
        uint256 montantRecolte;
        uint256 rembourseTotal;
        uint256 dureeEnSecondes;
        uint256 dateLimite;
        string justificatif;
        bool estFinance;
        bool estTermine;
        address[] investisseurs;
    }

    mapping(uint256 => Pret) public listeDesPrets;
    mapping(uint256 => mapping(address => uint256)) public contributions;
    
    uint256 public prochainId;

    // Fonction interne pour vérifier le lien Google Drive
    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        if (strBytes.length < prefixBytes.length) return false;
        for (uint i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }

    // --- 1. CRÉATION DE DEMANDE ---
    function creerDemande(uint256 _montant, string memory _lienDoc, uint256 _nbJours) public {
        require(_montant > 0, "Montant invalide");
        require(_nbJours >= 1 && _nbJours <= 90, "Duree doit etre entre 1 et 90 jours");
        require(_startsWith(_lienDoc, "https://drive.google.com/"), "Lien Google Drive requis");

        uint256 currentId = prochainId;
        Pret storage nouveauPret = listeDesPrets[currentId];
        nouveauPret.emprunteur = msg.sender;
        nouveauPret.montantDemande = _montant;
        nouveauPret.justificatif = _lienDoc;
        nouveauPret.dureeEnSecondes = _nbJours * 1 days; 
        nouveauPret.estFinance = false;
        nouveauPret.estTermine = false;

        prochainId++;
        emit DemandeCreee(currentId, msg.sender, _montant);
    }

    // --- 2. LOGIQUE D'INVESTISSEMENT ---
    function investir(uint256 _idPret) public payable {
        Pret storage monPret = listeDesPrets[_idPret];
        require(!monPret.estFinance, "Pret deja finance");
        require(msg.value > 0, "Envoyez de l'argent");
        require(monPret.montantRecolte + msg.value <= monPret.montantDemande, "Trop d'argent envoye");

        if (contributions[_idPret][msg.sender] == 0) {
            monPret.investisseurs.push(msg.sender);
        }
        contributions[_idPret][msg.sender] += msg.value;
        monPret.montantRecolte += msg.value;

        emit InvestissementRecu(_idPret, msg.sender, msg.value);

        if (monPret.montantRecolte == monPret.montantDemande) {
            monPret.estFinance = true;
            monPret.dateLimite = block.timestamp + monPret.dureeEnSecondes;
            
            (bool succes, ) = payable(monPret.emprunteur).call{value: monPret.montantRecolte}("");
            require(succes, "Echec de l'envoi a l'emprunteur");
            emit PretTotalementFinance(_idPret);
        }
    }

    // --- 3. REMBOURSEMENT ---
    function rembourser(uint256 _idPret) public payable {
        Pret storage monPret = listeDesPrets[_idPret];
        require(msg.sender == monPret.emprunteur, "Seul l'emprunteur peut rembourser");
        require(monPret.estFinance && !monPret.estTermine, "Etat du pret invalide");

        uint256 montantDu = monPret.montantDemande;
        if (block.timestamp > monPret.dateLimite) {
            montantDu = (montantDu * 105) / 100; // Pénalité 5%
        }

        monPret.rembourseTotal += msg.value;
        emit RemboursementRecu(_idPret, msg.sender, msg.value);

        if (monPret.rembourseTotal >= montantDu) {
            monPret.estTermine = true;
        }
    }

    // --- 4. RETRAIT DES GAINS ---
    function retirerGains(uint256 _idPret) public {
        Pret storage monPret = listeDesPrets[_idPret];
        require(monPret.estTermine, "Pret non encore termine");
        
        uint256 maPartInitiale = contributions[_idPret][msg.sender];
        require(maPartInitiale > 0, "Vous n'avez pas investi ici");

        uint256 montantARecuperer = (maPartInitiale * monPret.rembourseTotal) / monPret.montantDemande;
        contributions[_idPret][msg.sender] = 0;
        
        (bool succes, ) = payable(msg.sender).call{value: montantARecuperer}("");
        require(succes, "Echec du retrait");
        emit RetraitGainsEffectue(_idPret, msg.sender, montantARecuperer);
    }
}