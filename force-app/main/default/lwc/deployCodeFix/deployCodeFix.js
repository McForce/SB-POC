/**
 * deployCodeFix LWC
 * 
 * Placed on the Parent Log (rflib_Log__c) record page.
 * Displays a "Deploy Fix to GitHub" button that:
 *   1. Loads the recommended fix details from the record
 *   2. Shows a confirmation modal with the fix preview
 *   3. On confirmation, pushes the fix to GitHub via Apex
 *   4. Displays the resulting Pull Request link
 * 
 * @author  OneHub Platform Team
 * @date    2026-03-10
 */
import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFixDetails from '@salesforce/apex/GitHubCodeFixController.getFixDetails';
import deployFixToGitHub from '@salesforce/apex/GitHubCodeFixController.deployFixToGitHub';

export default class DeployCodeFix extends LightningElement {
    @api recordId;

    // State
    @track fixDetails = {};
    @track result = {};
    @track isLoading = false;
    @track showConfirmModal = false;
    @track showResultModal = false;
    @track errorMessage = '';

    // Wire adapter result for refresh
    wiredFixResult;

    // ─── Wire: Load fix details ─────────────────────────────────────

    @wire(getFixDetails, { recordId: '$recordId' })
    wiredGetFixDetails(result) {
        this.wiredFixResult = result;
        const { data, error } = result;

        if (data) {
            this.fixDetails = data;
            this.errorMessage = '';
        } else if (error) {
            this.errorMessage = this.extractError(error);
        }
    }

    // ─── Computed Properties ────────────────────────────────────────

    get hasFixAvailable() {
        return this.fixDetails.recommendedFix && this.fixDetails.filePath;
    }

    get isAlreadyDeployed() {
        return this.fixDetails.alreadyDeployed === true;
    }

    get buttonLabel() {
        if (this.isAlreadyDeployed) {
            return 'Fix Already Deployed';
        }
        return 'Deploy Fix to GitHub';
    }

    get buttonVariant() {
        if (this.isAlreadyDeployed) {
            return 'neutral';
        }
        return 'brand';
    }

    get isButtonDisabled() {
        return this.isAlreadyDeployed || !this.hasFixAvailable || this.isLoading;
    }

    get truncatedFix() {
        if (!this.fixDetails.recommendedFix) return '';
        const fix = this.fixDetails.recommendedFix;
        if (fix.length > 2000) {
            return fix.substring(0, 2000) + '\n\n... (truncated for preview)';
        }
        return fix;
    }

    get statusIconName() {
        if (this.isAlreadyDeployed) {
            return 'utility:check';
        }
        if (this.hasFixAvailable) {
            return 'utility:upload';
        }
        return 'utility:warning';
    }

    get statusMessage() {
        if (this.isAlreadyDeployed) {
            return 'This fix has been deployed to GitHub.';
        }
        if (this.hasFixAvailable) {
            return 'AI-recommended fix is ready for deployment.';
        }
        return 'No recommended fix available for this record.';
    }

    get resultIsSuccess() {
        return this.result && this.result.success === true;
    }

    // ─── Event Handlers ─────────────────────────────────────────────

    /**
     * Opens the confirmation modal when the Deploy button is clicked.
     */
    handleDeployClick() {
        if (this.isAlreadyDeployed || !this.hasFixAvailable) return;
        this.showConfirmModal = true;
    }

    /**
     * Closes the confirmation modal.
     */
    handleCancelDeploy() {
        this.showConfirmModal = false;
    }

    /**
     * Executes the GitHub deployment after user confirmation.
     */
    async handleConfirmDeploy() {
        this.showConfirmModal = false;
        this.isLoading = true;
        this.errorMessage = '';

        try {
            const deployResult = await deployFixToGitHub({ recordId: this.recordId });
            this.result = deployResult;

            if (deployResult.success) {
                this.showResultModal = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Code fix deployed to GitHub. Pull Request created.',
                        variant: 'success'
                    })
                );
                // Refresh the wire to update the UI state
                await refreshApex(this.wiredFixResult);
            } else {
                this.errorMessage = deployResult.errorMessage;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Deployment Failed',
                        message: deployResult.errorMessage,
                        variant: 'error',
                        mode: 'sticky'
                    })
                );
            }
        } catch (error) {
            this.errorMessage = this.extractError(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Closes the result modal.
     */
    handleCloseResult() {
        this.showResultModal = false;
    }

    /**
     * Opens the PR URL in a new tab.
     */
    handleOpenPr() {
        const url = this.result.pullRequestUrl || this.fixDetails.existingPrUrl;
        if (url) {
            window.open(url, '_blank');
        }
    }

    // ─── Utility ────────────────────────────────────────────────────

    extractError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unknown error occurred.';
    }
}